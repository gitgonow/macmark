//
//  MPRenderer.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 26/6.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPRenderer.h"
#import <limits.h>
#import <cmark-gfm.h>
#import <cmark-gfm-extension_api.h>
#import <HBHandlebars/HBHandlebars.h>
#import "cmark_macdown_extensions.h"
#import "NSJSONSerialization+File.h"
#import "NSObject+HTMLTabularize.h"
#import "NSString+Lookup.h"
#import "MPUtilities.h"
#import "MPAsset.h"
#import "MPPreferences.h"

// Warning: If the version of MathJax is ever updated, please check the status
// of https://github.com/mathjax/MathJax/issues/548. If the fix has been merged
// in to MathJax, then the WebResourceLoadDelegate can be removed from MPDocument
// and MathJax.js can be removed from this project.
static NSString * const kMPMathJaxCDN =
    @"https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.3/MathJax.js"
    @"?config=TeX-AMS-MML_HTMLorMML";
static NSString * const kMPPrismScriptDirectory = @"Prism/components";
static NSString * const kMPPrismThemeDirectory = @"Prism/themes";
static NSString * const kMPPrismPluginDirectory = @"Prism/plugins";
static int kMPRendererTOCLevel = 6;  // h1 to h6.


NS_INLINE NSURL *MPExtensionURL(NSString *name, NSString *extension)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url = [bundle URLForResource:name withExtension:extension
                           subdirectory:@"Extensions"];
    return url;
}

NS_INLINE NSURL *MPPrismPluginURL(NSString *name, NSString *extension)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *dirPath =
        [NSString stringWithFormat:@"%@/%@", kMPPrismPluginDirectory, name];

    NSString *filename = [NSString stringWithFormat:@"prism-%@.min", name];
    NSURL *url = [bundle URLForResource:filename withExtension:extension
                           subdirectory:dirPath];
    if (url)
        return url;

    filename = [NSString stringWithFormat:@"prism-%@", name];
    url = [bundle URLForResource:filename withExtension:extension
                    subdirectory:dirPath];
    return url;
}

NS_INLINE NSArray *MPPrismScriptURLsForLanguage(NSString *language)
{
    NSURL *baseUrl = nil;
    NSURL *extraUrl = nil;
    NSBundle *bundle = [NSBundle mainBundle];

    language = [language lowercaseString];
    NSString *baseFileName =
        [NSString stringWithFormat:@"prism-%@", language];
    NSString *extraFileName =
        [NSString stringWithFormat:@"prism-%@-extras", language];

    for (NSString *ext in @[@"min.js", @"js"])
    {
        if (!baseUrl)
        {
            baseUrl = [bundle URLForResource:baseFileName withExtension:ext
                                subdirectory:kMPPrismScriptDirectory];
        }
        if (!extraUrl)
        {
            extraUrl = [bundle URLForResource:extraFileName withExtension:ext
                                 subdirectory:kMPPrismScriptDirectory];
        }
    }

    NSMutableArray *urls = [NSMutableArray array];
    if (baseUrl)
        [urls addObject:baseUrl];
    if (extraUrl)
        [urls addObject:extraUrl];
    return urls;
}

#pragma mark - MathJax Pre/Post Processing

// Extract math blocks ($...$, $$...$$) before cmark parsing to prevent
// them from being interpreted as markdown. Replace with placeholders,
// then restore after HTML rendering.
NS_INLINE NSString *MPPreProcessMathJax(NSString *text,
                                         NSMutableArray *mathBlocks,
                                         BOOL inlineDollar)
{
    if (!text.length)
        return text;

    NSMutableString *result = [text mutableCopy];

    // Process display math first ($$...$$)
    {
        NSRegularExpression *regex =
            [NSRegularExpression regularExpressionWithPattern:
                @"\\$\\$(.+?)\\$\\$"
                options:NSRegularExpressionDotMatchesLineSeparators
                  error:NULL];
        NSArray *matches = [regex matchesInString:result options:0
                                            range:NSMakeRange(0, result.length)];
        // Replace in reverse order to preserve indices
        for (NSTextCheckingResult *match in [matches reverseObjectEnumerator])
        {
            NSString *fullMatch = [result substringWithRange:match.range];
            NSUInteger index = mathBlocks.count;
            [mathBlocks addObject:fullMatch];
            NSString *placeholder = [NSString stringWithFormat:
                @"MACDOWN_MATH_PLACEHOLDER_%lu", (unsigned long)index];
            [result replaceCharactersInRange:match.range withString:placeholder];
        }
    }

    // Process inline math ($...$) if enabled
    if (inlineDollar)
    {
        NSRegularExpression *regex =
            [NSRegularExpression regularExpressionWithPattern:
                @"(?<!\\\\)\\$(?!\\$)(.+?)(?<!\\\\)\\$(?!\\$)"
                options:0 error:NULL];
        NSArray *matches = [regex matchesInString:result options:0
                                            range:NSMakeRange(0, result.length)];
        for (NSTextCheckingResult *match in [matches reverseObjectEnumerator])
        {
            NSString *fullMatch = [result substringWithRange:match.range];
            NSUInteger index = mathBlocks.count;
            [mathBlocks addObject:fullMatch];
            NSString *placeholder = [NSString stringWithFormat:
                @"MACDOWN_MATH_PLACEHOLDER_%lu", (unsigned long)index];
            [result replaceCharactersInRange:match.range withString:placeholder];
        }
    }

    return result;
}

NS_INLINE NSString *MPPostProcessMathJax(NSString *html,
                                          NSArray *mathBlocks)
{
    if (!mathBlocks.count)
        return html;

    NSMutableString *result = [html mutableCopy];
    for (NSUInteger i = 0; i < mathBlocks.count; i++)
    {
        NSString *placeholder = [NSString stringWithFormat:
            @"MACDOWN_MATH_PLACEHOLDER_%lu", (unsigned long)i];
        [result replaceOccurrencesOfString:placeholder
                                withString:mathBlocks[i]
                                   options:0
                                     range:NSMakeRange(0, result.length)];
    }
    return result;
}

#pragma mark - Code Block Post-Processing

// Post-process cmark HTML to wrap code blocks in <div> with Prism-compatible
// markup matching the old hoedown_html_patch output format:
//   <div><pre class="line-numbers" data-information="..."><code class="language-X">
NS_INLINE NSString *MPPostProcessCodeBlocks(NSString *html,
                                             BOOL lineNumbers,
                                             BOOL hasInformation)
{
    if (!html.length)
        return html;

    // cmark-gfm produces: <pre><code class="language-X">...</code></pre>
    // We need: <div><pre [class="line-numbers"] [data-information="..."]><code class="language-X">...</code></pre></div>

    NSMutableString *result = [html mutableCopy];

    // Match <pre><code class="language-LANG:INFO"> or <pre><code class="language-LANG">
    // or <pre><code> (no language)
    NSString *pattern = @"<pre><code(?:\\s+class=\"language-([^\"]*)\")?>";
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern options:0
                                                    error:NULL];

    NSArray *matches = [regex matchesInString:result options:0
                                        range:NSMakeRange(0, result.length)];

    // Replace in reverse to preserve offsets
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator])
    {
        NSString *langFull = nil;
        if (match.numberOfRanges > 1 && [match rangeAtIndex:1].location != NSNotFound)
            langFull = [result substringWithRange:[match rangeAtIndex:1]];

        NSString *lang = langFull;
        NSString *info = nil;

        // Split language:information if information mode is active
        if (hasInformation && lang)
        {
            NSRange colonRange = [lang rangeOfString:@":"];
            if (colonRange.location != NSNotFound)
            {
                info = [lang substringFromIndex:colonRange.location + 1];
                lang = [lang substringToIndex:colonRange.location];
            }
        }

        // Build replacement
        NSMutableString *replacement = [NSMutableString stringWithString:@"<div><pre"];
        if (lineNumbers)
            [replacement appendString:@" class=\"line-numbers\""];
        if (info.length)
            [replacement appendFormat:@" data-information=\"%@\"", info];
        [replacement appendString:@"><code class=\"language-"];
        [replacement appendString:(lang.length ? lang : @"none")];
        [replacement appendString:@"\">"];

        [result replaceCharactersInRange:match.range withString:replacement];
    }

    // Close: replace </code></pre> with </code></pre></div>
    [result replaceOccurrencesOfString:@"</code></pre>"
                            withString:@"</code></pre></div>"
                               options:0
                                 range:NSMakeRange(0, result.length)];

    return result;
}

#pragma mark - TOC Generation

// Walk the cmark AST to generate a TOC matching hoedown's output format.
NS_INLINE NSString *MPGenerateTOC(cmark_node *doc)
{
    NSMutableString *toc = [NSMutableString string];
    int currentLevel = 0;
    int levelOffset = 0;
    int headerCount = 0;

    cmark_iter *iter = cmark_iter_new(doc);
    cmark_event_type ev;
    cmark_node *node;

    while ((ev = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        node = cmark_iter_get_node(iter);
        if (ev != CMARK_EVENT_ENTER)
            continue;
        if (cmark_node_get_type(node) != CMARK_NODE_HEADING)
            continue;

        int level = cmark_node_get_heading_level(node);
        if (level > kMPRendererTOCLevel)
            continue;

        // Set offset from first heading
        if (currentLevel == 0)
            levelOffset = level - 1;

        level -= levelOffset;

        // Get heading text content
        NSMutableString *headingText = [NSMutableString string];
        cmark_node *child = cmark_node_first_child(node);
        while (child) {
            if (cmark_node_get_type(child) == CMARK_NODE_TEXT) {
                const char *literal = cmark_node_get_literal(child);
                if (literal)
                    [headingText appendString:
                        [NSString stringWithUTF8String:literal]];
            } else if (cmark_node_get_type(child) == CMARK_NODE_CODE) {
                const char *literal = cmark_node_get_literal(child);
                if (literal)
                    [headingText appendString:
                        [NSString stringWithUTF8String:literal]];
            } else {
                // For inline elements (emphasis, strong, etc.), recurse
                // into children to extract text
                cmark_iter *innerIter = cmark_iter_new(child);
                cmark_event_type innerEv;
                cmark_node *innerNode;
                while ((innerEv = cmark_iter_next(innerIter)) != CMARK_EVENT_DONE) {
                    innerNode = cmark_iter_get_node(innerIter);
                    if (innerEv == CMARK_EVENT_ENTER &&
                        (cmark_node_get_type(innerNode) == CMARK_NODE_TEXT ||
                         cmark_node_get_type(innerNode) == CMARK_NODE_CODE)) {
                        const char *literal = cmark_node_get_literal(innerNode);
                        if (literal)
                            [headingText appendString:
                                [NSString stringWithUTF8String:literal]];
                    }
                }
                cmark_iter_free(innerIter);
            }
            child = cmark_node_next(child);
        }

        if (level > currentLevel) {
            while (level > currentLevel) {
                if (currentLevel == 0)
                    [toc appendString:@"<ul class=\"toc\">\n<li>\n"];
                else
                    [toc appendString:@"<ul>\n<li>\n"];
                currentLevel++;
            }
        } else if (level < currentLevel) {
            [toc appendString:@"</li>\n"];
            while (level < currentLevel) {
                [toc appendString:@"</ul>\n</li>\n"];
                currentLevel--;
            }
            [toc appendString:@"<li>\n"];
        } else {
            [toc appendString:@"</li>\n<li>\n"];
        }

        [toc appendFormat:@"<a href=\"#toc_%d\">%@</a>\n", headerCount++,
            headingText];
    }

    // Close remaining open tags
    while (currentLevel > 0) {
        [toc appendString:@"</li>\n</ul>\n"];
        currentLevel--;
    }

    cmark_iter_free(iter);
    return toc;
}

#pragma mark - Language Extraction from AST

NS_INLINE void MPExtractLanguagesFromAST(cmark_node *doc,
                                          NSMutableArray *languages,
                                          NSDictionary *aliasMap,
                                          NSDictionary *languageMap)
{
    cmark_iter *iter = cmark_iter_new(doc);
    cmark_event_type ev;
    cmark_node *node;

    while ((ev = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        node = cmark_iter_get_node(iter);
        if (ev != CMARK_EVENT_ENTER)
            continue;
        if (cmark_node_get_type(node) != CMARK_NODE_CODE_BLOCK)
            continue;

        const char *fence_info = cmark_node_get_fence_info(node);
        if (!fence_info || !fence_info[0])
            continue;

        NSString *lang = [NSString stringWithUTF8String:fence_info];
        // Strip everything after colon (info string)
        NSRange colonRange = [lang rangeOfString:@":"];
        if (colonRange.location != NSNotFound)
            lang = [lang substringToIndex:colonRange.location];

        // Resolve alias
        if ([aliasMap objectForKey:lang])
            lang = aliasMap[lang];

        // Add language and its dependencies
        // Move language to root of dependencies
        NSUInteger index = [languages indexOfObject:lang];
        if (index != NSNotFound)
            [languages removeObjectAtIndex:index];
        [languages insertObject:lang atIndex:0];

        // Add dependencies
        id require = languageMap[lang][@"require"];
        if ([require isKindOfClass:[NSString class]])
        {
            NSUInteger idx = [languages indexOfObject:require];
            if (idx != NSNotFound)
                [languages removeObjectAtIndex:idx];
            [languages insertObject:require atIndex:0];
        }
        else if ([require isKindOfClass:[NSArray class]])
        {
            for (NSString *dep in require) {
                NSUInteger idx = [languages indexOfObject:dep];
                if (idx != NSNotFound)
                    [languages removeObjectAtIndex:idx];
                [languages insertObject:dep atIndex:0];
            }
        }
    }

    cmark_iter_free(iter);
}

#pragma mark - Main Rendering

NS_INLINE NSString *MPHTMLFromMarkdown(
    NSString *text, int options, cmark_llist *extensions,
    BOOL hasTOC, NSString *frontMatter,
    NSMutableArray *languages, BOOL hasMathJax, BOOL mathJaxInlineDollar,
    BOOL lineNumbers, BOOL hasInformation)
{
    // Pre-process MathJax
    NSMutableArray *mathBlocks = [NSMutableArray array];
    if (hasMathJax)
        text = MPPreProcessMathJax(text, mathBlocks, mathJaxInlineDollar);

    NSData *inputData = [text dataUsingEncoding:NSUTF8StringEncoding];

    // Create parser and attach extensions
    cmark_parser *parser = cmark_parser_new(options);

    cmark_llist *cur = extensions;
    while (cur) {
        cmark_syntax_extension *ext = (cmark_syntax_extension *)cur->data;
        cmark_parser_attach_syntax_extension(parser, ext);
        cur = cur->next;
    }

    // Parse
    cmark_parser_feed(parser, (const char *)inputData.bytes, inputData.length);
    cmark_node *doc = cmark_parser_finish(parser);

    // Extract languages for Prism before rendering
    static NSDictionary *aliasMap = nil;
    static NSDictionary *languageMap = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSURL *url = [bundle URLForResource:@"syntax_highlighting"
                              withExtension:@"json"];
        NSDictionary *info =
            [NSJSONSerialization JSONObjectWithFileAtURL:url options:0
                                                   error:NULL];
        aliasMap = info[@"aliases"];

        url = [bundle URLForResource:@"components" withExtension:@"js"
                        subdirectory:@"Prism"];
        NSString *code = [NSString stringWithContentsOfURL:url
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
        NSDictionary *comp = MPGetObjectFromJavaScript(code, @"components");
        languageMap = comp[@"languages"];
    });

    MPExtractLanguagesFromAST(doc, languages, aliasMap, languageMap);

    // Generate TOC from AST before rendering
    NSString *toc = nil;
    if (hasTOC)
        toc = MPGenerateTOC(doc);

    // Render HTML
    char *htmlCStr = cmark_render_html(doc, options,
                                        cmark_parser_get_syntax_extensions(parser));
    NSString *result = [NSString stringWithUTF8String:htmlCStr];
    free(htmlCStr);

    cmark_node_free(doc);
    cmark_parser_free(parser);

    // Post-process code blocks for Prism compatibility
    result = MPPostProcessCodeBlocks(result, lineNumbers, hasInformation);

    // Post-process MathJax
    if (hasMathJax)
        result = MPPostProcessMathJax(result, mathBlocks);

    // Replace [TOC] markers
    if (hasTOC && toc)
    {
        static NSRegularExpression *tocRegex = nil;
        static dispatch_once_t tocOnceToken;
        dispatch_once(&tocOnceToken, ^{
            NSString *pattern = @"<p.*?>\\s*\\[TOC\\]\\s*</p>";
            NSRegularExpressionOptions ops = NSRegularExpressionCaseInsensitive;
            tocRegex = [[NSRegularExpression alloc] initWithPattern:pattern
                                                            options:ops
                                                              error:NULL];
        });
        NSRange replaceRange = NSMakeRange(0, result.length);
        result = [tocRegex stringByReplacingMatchesInString:result options:0
                                                      range:replaceRange
                                               withTemplate:toc];
    }

    if (frontMatter)
        result = [NSString stringWithFormat:@"%@\n%@", frontMatter, result];

    return result;
}

NS_INLINE NSString *MPGetHTML(
    NSString *title, NSString *body, NSArray *styles, MPAssetOption styleopt,
    NSArray *scripts, MPAssetOption scriptopt)
{
    NSMutableArray *styleTags = [NSMutableArray array];
    NSMutableArray *scriptTags = [NSMutableArray array];
    for (MPStyleSheet *style in styles)
    {
        NSString *s = [style htmlForOption:styleopt];
        if (s)
            [styleTags addObject:s];
    }
    for (MPScript *script in scripts)
    {
        NSString *s = [script htmlForOption:scriptopt];
        if (s)
            [scriptTags addObject:s];
    }

    MPPreferences *preferences = [MPPreferences sharedInstance];

    static NSString *f = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        NSURL *url = [bundle URLForResource:preferences.htmlTemplateName
                              withExtension:@".handlebars"
                               subdirectory:@"Templates"];
        f = [NSString stringWithContentsOfURL:url
                                     encoding:NSUTF8StringEncoding error:NULL];
    });
    NSCAssert(f.length, @"Could not read template");

    NSString *titleTag = @"";
    if (title.length)
        titleTag = [NSString stringWithFormat:@"<title>%@</title>", title];

    NSDictionary *context = @{
        @"title": title ? title : @"",
        @"titleTag": titleTag ? titleTag : @"",
        @"styleTags": styleTags ? styleTags : @[],
        @"body": body ? body : @"",
        @"scriptTags": scriptTags ? scriptTags : @[],
    };
    NSString *html = [HBHandlebars renderTemplateString:f withContext:context
                                                  error:NULL];
    return html;
}

NS_INLINE BOOL MPAreNilableStringsEqual(NSString *s1, NSString *s2)
{
    // The == part takes care of cases where s1 and s2 are both nil.
    return ([s1 isEqualToString:s2] || s1 == s2);
}


@interface MPRenderer ()

@property (strong) NSMutableArray *currentLanguages;
@property (readonly) NSArray *baseStylesheets;
@property (readonly) NSArray *prismStylesheets;
@property (readonly) NSArray *prismScripts;
@property (readonly) NSArray *mathjaxScripts;
@property (readonly) NSArray *mermaidStylesheets;
@property (readonly) NSArray *mermaidScripts;
@property (readonly) NSArray *graphvizScripts;
@property (readonly) NSArray *stylesheets;
@property (readonly) NSArray *scripts;
@property (copy) NSString *currentHtml;
@property (strong) NSOperationQueue *parseQueue;
@property int extensions;
@property BOOL smartypants;
@property BOOL TOC;
@property (copy) NSString *styleName;
@property BOOL frontMatter;
@property BOOL syntaxHighlighting;
@property BOOL mermaid;
@property BOOL graphviz;
@property MPCodeBlockAccessoryType codeBlockAccesory;
@property BOOL lineNumbers;
@property BOOL manualRender;
@property (copy) NSString *highlightingThemeName;

@end


@implementation MPRenderer

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self.currentHtml = @"";
    self.currentLanguages = [NSMutableArray array];
    self.parseQueue = [[NSOperationQueue alloc] init];
    self.parseQueue.maxConcurrentOperationCount = 1; // Serial queue

    // Ensure all cmark-gfm extensions are registered once.
    cmark_macdown_extensions_ensure_registered();

    return self;
}

#pragma mark - Accessor

- (NSArray *)baseStylesheets
{
    NSString *defaultStyleName =
        MPStylePathForName([self.delegate rendererStyleName:self]);
    if (!defaultStyleName)
        return @[];
    NSURL *defaultStyle = [NSURL fileURLWithPath:defaultStyleName];
    NSMutableArray *stylesheets = [NSMutableArray array];
    [stylesheets addObject:[MPStyleSheet CSSWithURL:defaultStyle]];
    return stylesheets;
}

- (NSArray *)prismStylesheets
{
    NSString *name = [self.delegate rendererHighlightingThemeName:self];
    MPAsset *stylesheet =
        [MPStyleSheet CSSWithURL:MPHighlightingThemeURLForName(name)];

    NSMutableArray *stylesheets = [NSMutableArray arrayWithObject:stylesheet];

    if (self.rendererFlags & (1 << 1)) // line numbers flag
    {
        NSURL *url = MPPrismPluginURL(@"line-numbers", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }
    if ([self.delegate rendererCodeBlockAccesory:self]
        == MPCodeBlockAccessoryLanguageName)
    {
        NSURL *url = MPPrismPluginURL(@"show-language", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }

    return stylesheets;
}

- (NSArray *)prismScripts
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *url = [bundle URLForResource:@"prism-core.min" withExtension:@"js"
                           subdirectory:kMPPrismScriptDirectory];
    MPAsset *script = [MPScript javaScriptWithURL:url];
    NSMutableArray *scripts = [NSMutableArray arrayWithObject:script];
    for (NSString *language in self.currentLanguages)
    {
        for (NSURL *url in MPPrismScriptURLsForLanguage(language))
            [scripts addObject:[MPScript javaScriptWithURL:url]];
    }

    if (self.rendererFlags & (1 << 1)) // line numbers flag
    {
        NSURL *url = MPPrismPluginURL(@"line-numbers", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    if ([self.delegate rendererCodeBlockAccesory:self]
        == MPCodeBlockAccessoryLanguageName)
    {
        NSURL *url = MPPrismPluginURL(@"show-language", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    return scripts;
}

- (NSArray *)mathjaxScripts
{
    NSMutableArray *scripts = [NSMutableArray array];
    NSURL *url = [NSURL URLWithString:kMPMathJaxCDN];
    NSBundle *bundle = [NSBundle mainBundle];
    MPEmbeddedScript *script =
        [MPEmbeddedScript assetWithURL:[bundle URLForResource:@"init"
                                                withExtension:@"js"
                                                 subdirectory:@"MathJax"]
                               andType:kMPMathJaxConfigType];
    [scripts addObject:script];
    [scripts addObject:[MPScript javaScriptWithURL:url]];
    return scripts;
}

- (NSArray *)mermaidStylesheets
{
    NSMutableArray *stylesheets = [NSMutableArray array];

    NSURL *url = MPExtensionURL(@"mermaid.forest", @"css");
    [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];

    return stylesheets;
}

- (NSArray *)mermaidScripts
{
    NSMutableArray *scripts = [NSMutableArray array];

    {
        NSURL *url = MPExtensionURL(@"mermaid.min", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    {
        NSURL *url = MPExtensionURL(@"mermaid.init", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }

    return scripts;
}

- (NSArray *)graphvizScripts
{
    NSMutableArray *scripts = [NSMutableArray array];

    {
        NSURL *url = MPExtensionURL(@"viz", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    {
        NSURL *url = MPExtensionURL(@"viz.init", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }

    return scripts;
}

- (NSArray *)stylesheets
{
    id<MPRendererDelegate> delegate = self.delegate;

    NSMutableArray *stylesheets = [self.baseStylesheets mutableCopy];
    if ([delegate rendererHasSyntaxHighlighting:self])
    {
        [stylesheets addObjectsFromArray:self.prismStylesheets];
        // mermaid
        if ([delegate rendererHasMermaid:self])
        {
            [stylesheets addObjectsFromArray:self.mermaidStylesheets];
        }

    }

    if ([delegate rendererCodeBlockAccesory:self] == MPCodeBlockAccessoryCustom)
    {
        NSURL *url = MPExtensionURL(@"show-information", @"css");
        [stylesheets addObject:[MPStyleSheet CSSWithURL:url]];
    }
    return stylesheets;
}

- (NSArray *)scripts
{
    id<MPRendererDelegate> d = self.delegate;
    NSMutableArray *scripts = [NSMutableArray array];
    if (self.rendererFlags & (1 << 0)) // task list flag
    {
        NSURL *url = MPExtensionURL(@"tasklist", @"js");
        [scripts addObject:[MPScript javaScriptWithURL:url]];
    }
    if ([d rendererHasSyntaxHighlighting:self])
    {
        [scripts addObjectsFromArray:self.prismScripts];
        // mermaid
        if ([d rendererHasMermaid:self])
        {
            [scripts addObjectsFromArray:self.mermaidScripts];
        }
        // graphviz
        if ([d rendererHasGraphviz:self])
        {
            [scripts addObjectsFromArray:self.graphvizScripts];
        }
    }
    if ([d rendererHasMathJax:self])
        [scripts addObjectsFromArray:self.mathjaxScripts];
    return scripts;
}

#pragma mark - Public

- (void)parseAndRenderWithMaxDelay:(NSTimeInterval)maxDelay {
    [self.parseQueue cancelAllOperations];
    [self.parseQueue addOperationWithBlock:^{
        // Fetch the markdown (from the main thread)
        __block NSString *markdown;
        dispatch_sync(dispatch_get_main_queue(), ^{
            markdown = [[self.dataSource rendererMarkdown:self] copy];
        });

        // Parse in backgound
        [self parseMarkdown:markdown];

        // Wait for renderer to finish loading, up to maxDelay seconds.
        if (maxDelay > 0) {
            NSDate *start = [NSDate date];
            __block BOOL rendererIsLoading = YES;
            while (rendererIsLoading && -[start timeIntervalSinceNow] < maxDelay) {
                usleep(10000); // 10ms sleep to avoid busy-spinning
                dispatch_sync(dispatch_get_main_queue(), ^{
                    rendererIsLoading = [self.dataSource rendererLoading];
                });
            }
        }

        // Render on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self render];
        });
    }];
}

- (void)parseAndRenderNow
{
    [self parseAndRenderWithMaxDelay:0];
}

- (void)parseAndRenderLater
{
    [self parseAndRenderWithMaxDelay:0.5];
}

- (void)parseIfPreferencesChanged
{
    id<MPRendererDelegate> delegate = self.delegate;
    if ([delegate rendererExtensions:self] != self.extensions
            || [delegate rendererHasSmartyPants:self] != self.smartypants
            || [delegate rendererRendersTOC:self] != self.TOC
            || [delegate rendererDetectsFrontMatter:self] != self.frontMatter)
    {
        [self parseMarkdown:[self.dataSource rendererMarkdown:self]];
    }
}

- (void)parseMarkdown:(NSString *)markdown {
    [self.currentLanguages removeAllObjects];

    id<MPRendererDelegate> delegate = self.delegate;
    int extensions = [delegate rendererExtensions:self];
    BOOL smartypants = [delegate rendererHasSmartyPants:self];
    BOOL hasFrontMatter = [delegate rendererDetectsFrontMatter:self];
    BOOL hasTOC = [delegate rendererRendersTOC:self];
    BOOL hasMathJax = [delegate rendererHasMathJax:self];

    id frontMatter = nil;
    if (hasFrontMatter)
    {
        NSUInteger offset = 0;
        frontMatter = [markdown frontMatter:&offset];
        markdown = [markdown substringFromIndex:offset];
    }

    // Build cmark options
    int cmarkOptions = CMARK_OPT_DEFAULT;
    if (smartypants)
        cmarkOptions |= CMARK_OPT_SMART;
    if (self.rendererFlags & (1 << 2)) // hard wrap flag
        cmarkOptions |= CMARK_OPT_HARDBREAKS;
    if (extensions & (1 << 10)) // footnotes flag
        cmarkOptions |= CMARK_OPT_FOOTNOTES;

    // Build extension list
    cmark_mem *mem = cmark_get_default_mem_allocator();
    cmark_llist *extList = NULL;

    if (extensions & (1 << 0)) // autolink
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("autolink");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }
    if (extensions & (1 << 1)) // tables
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("table");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }
    if (extensions & (1 << 2)) // strikethrough
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("strikethrough");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }
    if (extensions & (1 << 3)) // superscript
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("superscript");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }
    if (extensions & (1 << 4)) // highlight
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("highlight");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }
    if (extensions & (1 << 5)) // quote
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("quote");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }
    if (extensions & (1 << 6)) // underline
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("underline");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }
    if (self.rendererFlags & (1 << 0)) // task list
    {
        cmark_syntax_extension *ext = cmark_find_syntax_extension("tasklist");
        if (ext) extList = cmark_llist_append(mem, extList, ext);
    }

    // Check for MathJax inline dollar preference
    MPPreferences *prefs = [MPPreferences sharedInstance];
    BOOL mathJaxInlineDollar = prefs.htmlMathJaxInlineDollar;

    BOOL lineNumbers = (self.rendererFlags & (1 << 1)) != 0;
    BOOL hasInformation = (self.rendererFlags & (1 << 3)) != 0;

    self.currentHtml = MPHTMLFromMarkdown(
        markdown, cmarkOptions, extList,
        hasTOC, [frontMatter HTMLTable],
        self.currentLanguages, hasMathJax, mathJaxInlineDollar,
        lineNumbers, hasInformation);

    if (extList)
        cmark_llist_free(mem, extList);

    self.extensions = extensions;
    self.smartypants = smartypants;
    self.TOC = hasTOC;
    self.frontMatter = hasFrontMatter;
}

- (void)renderIfPreferencesChanged
{
    BOOL changed = NO;
    id<MPRendererDelegate> d = self.delegate;
    if ([d rendererHasSyntaxHighlighting:self] != self.syntaxHighlighting)
        changed = YES;
    else if ([d rendererHasMermaid:self] != self.mermaid)
        changed = YES;
    else if ([d rendererHasGraphviz:self] != self.graphviz)
        changed = YES;
    else if (!MPAreNilableStringsEqual(
            [d rendererHighlightingThemeName:self], self.highlightingThemeName))
        changed = YES;
    else if (!MPAreNilableStringsEqual(
            [d rendererStyleName:self], self.styleName))
        changed = YES;
    else if ([d rendererCodeBlockAccesory:self] != self.codeBlockAccesory)
        changed = YES;

    if (changed)
        [self render];
}

- (void)render
{
    id<MPRendererDelegate> delegate = self.delegate;

    NSString *title = [self.dataSource rendererHTMLTitle:self];
    NSString *html = MPGetHTML(
        title, self.currentHtml, self.stylesheets, MPAssetFullLink,
        self.scripts, MPAssetFullLink);
    [delegate renderer:self didProduceHTMLOutput:html];

    self.styleName = [delegate rendererStyleName:self];
    self.syntaxHighlighting = [delegate rendererHasSyntaxHighlighting:self];
    self.mermaid = [delegate rendererHasMermaid:self];
    self.graphviz = [delegate rendererHasGraphviz:self];
    self.highlightingThemeName = [delegate rendererHighlightingThemeName:self];
    self.codeBlockAccesory = [delegate rendererCodeBlockAccesory:self];
}

- (NSString *)HTMLForExportWithStyles:(BOOL)withStyles
                         highlighting:(BOOL)withHighlighting
{
    MPAssetOption stylesOption = MPAssetNone;
    MPAssetOption scriptsOption = MPAssetNone;
    NSMutableArray *styles = [NSMutableArray array];
    NSMutableArray *scripts = [NSMutableArray array];

    if (withStyles)
    {
        stylesOption = MPAssetEmbedded;
        [styles addObjectsFromArray:self.baseStylesheets];
    }
    if (withHighlighting)
    {
        stylesOption = MPAssetEmbedded;
        scriptsOption = MPAssetEmbedded;
        [styles addObjectsFromArray:self.prismStylesheets];
        [scripts addObjectsFromArray:self.prismScripts];
        if ([self.delegate rendererHasMermaid:self])
        {
            [styles addObjectsFromArray:self.mermaidStylesheets];
            [scripts addObjectsFromArray:self.mermaidScripts];
        }
        if ([self.delegate rendererHasGraphviz:self])
        {
            [scripts addObjectsFromArray:self.graphvizScripts];
        }

    }
    if ([self.delegate rendererHasMathJax:self])
    {
        scriptsOption = MPAssetEmbedded;
        [scripts addObjectsFromArray:self.mathjaxScripts];
    }

    NSString *title = [self.dataSource rendererHTMLTitle:self];
    if (!title)
        title = @"";
    NSString *html = MPGetHTML(
        title, self.currentHtml, styles, stylesOption, scripts, scriptsOption);
    return html;
}

@end
