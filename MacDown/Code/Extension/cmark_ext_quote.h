#ifndef CMARK_EXT_QUOTE_H
#define CMARK_EXT_QUOTE_H

#include "cmark-gfm-extension_api.h"

extern cmark_node_type CMARK_NODE_INLINE_QUOTE;
cmark_syntax_extension *create_quote_extension(void);

#endif
