#ifndef CMARK_MACDOWN_EXTENSIONS_H
#define CMARK_MACDOWN_EXTENSIONS_H

// Registers all cmark-gfm core extensions (table, strikethrough, autolink,
// tasklist, tagfilter) plus MacDown custom extensions (superscript, highlight,
// quote, underline). After calling this, extensions can be found by name with
// cmark_find_syntax_extension().
void cmark_macdown_extensions_ensure_registered(void);

#endif
