#ifndef CMARK_EXT_UNDERLINE_H
#define CMARK_EXT_UNDERLINE_H

#include "cmark-gfm-extension_api.h"

extern cmark_node_type CMARK_NODE_UNDERLINE;
cmark_syntax_extension *create_underline_extension(void);

#endif
