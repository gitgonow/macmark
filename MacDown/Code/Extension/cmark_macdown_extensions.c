#include "cmark_macdown_extensions.h"
#include "cmark-gfm-core-extensions.h"
#include "cmark_ext_superscript.h"
#include "cmark_ext_highlight.h"
#include "cmark_ext_quote.h"
#include "cmark_ext_underline.h"
#include <registry.h>
#include <plugin.h>

static int macdown_extensions_registration(cmark_plugin *plugin) {
  cmark_plugin_register_syntax_extension(plugin, create_superscript_extension());
  cmark_plugin_register_syntax_extension(plugin, create_highlight_extension());
  cmark_plugin_register_syntax_extension(plugin, create_quote_extension());
  cmark_plugin_register_syntax_extension(plugin, create_underline_extension());
  return 1;
}

void cmark_macdown_extensions_ensure_registered(void) {
  static int registered = 0;

  if (!registered) {
    // Register the built-in GFM core extensions (table, strikethrough,
    // autolink, tasklist, tagfilter).
    cmark_gfm_core_extensions_ensure_registered();

    // Register MacDown custom extensions (superscript, highlight, quote,
    // underline).
    cmark_register_plugin(macdown_extensions_registration);

    registered = 1;
  }
}
