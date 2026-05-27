#ifndef CMARK_EXT_HIGHLIGHT_H
#define CMARK_EXT_HIGHLIGHT_H

#include "cmark-gfm-extension_api.h"

extern cmark_node_type CMARK_NODE_HIGHLIGHT;
cmark_syntax_extension *create_highlight_extension(void);

#endif
