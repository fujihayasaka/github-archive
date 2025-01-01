## ui/packages/syntax-highlighted-line

The `ui/packages/syntax-highlighted-line` package provides syntax highlighting capabilities for code lines when provided styling directves and raw codes lines.

Where possible it uses the CSS Custom Highlighting API to apply the highlighting. In the cases where the browser feature is not supported or there is no browser available (ie - SSR), it will fall back to building the highlighting with DOM elements + css classes.

**Disclaimer:** This package is still in development and is not ready for consumption. Use it with caution as features and APIs may change in future releases.
