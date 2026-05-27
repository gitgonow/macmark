// Underline extension for cmark-gfm.
//
// Because _ is deeply integrated into cmark's emphasis handling, this extension
// uses a post-processing approach: after the AST is built, it walks the tree
// and converts CMARK_NODE_EMPH nodes whose delimiter was _ into underline nodes.
// This avoids fighting with the core emphasis parser.
//
// When the underline extension is active, single-underscore emphasis becomes <u>.

#include "cmark_ext_underline.h"
#include <parser.h>
#include <render.h>

cmark_node_type CMARK_NODE_UNDERLINE;

static cmark_node *postprocess(cmark_syntax_extension *ext, cmark_parser *parser,
                               cmark_node *root) {
  // Walk the AST and convert CMARK_NODE_EMPH to CMARK_NODE_UNDERLINE.
  // We only do this when the extension is active.
  cmark_iter *iter = cmark_iter_new(root);
  cmark_event_type ev;
  cmark_node *node;

  while ((ev = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    node = cmark_iter_get_node(iter);
    if (ev == CMARK_EVENT_ENTER && cmark_node_get_type(node) == CMARK_NODE_EMPH) {
      // Convert emphasis to underline
      cmark_node_set_type(node, CMARK_NODE_UNDERLINE);
      cmark_node_set_syntax_extension(node, ext);
    }
  }

  cmark_iter_free(iter);
  return root;
}

static const char *get_type_string(cmark_syntax_extension *extension,
                                   cmark_node *node) {
  return node->type == CMARK_NODE_UNDERLINE ? "underline" : "<unknown>";
}

static int can_contain(cmark_syntax_extension *extension, cmark_node *node,
                       cmark_node_type child_type) {
  if (node->type != CMARK_NODE_UNDERLINE)
    return false;

  return CMARK_NODE_TYPE_INLINE_P(child_type);
}

static void html_render(cmark_syntax_extension *extension,
                        cmark_html_renderer *renderer, cmark_node *node,
                        cmark_event_type ev_type, int options) {
  bool entering = (ev_type == CMARK_EVENT_ENTER);
  if (entering) {
    cmark_strbuf_puts(renderer->html, "<u>");
  } else {
    cmark_strbuf_puts(renderer->html, "</u>");
  }
}

cmark_syntax_extension *create_underline_extension(void) {
  cmark_syntax_extension *ext = cmark_syntax_extension_new("underline");

  cmark_syntax_extension_set_get_type_string_func(ext, get_type_string);
  cmark_syntax_extension_set_can_contain_func(ext, can_contain);
  cmark_syntax_extension_set_html_render_func(ext, html_render);
  cmark_syntax_extension_set_postprocess_func(ext, postprocess);
  CMARK_NODE_UNDERLINE = cmark_syntax_extension_add_node(1);

  return ext;
}
