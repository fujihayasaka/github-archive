import type {StylingDirective} from '../types'

export function addHighlight(directive: StylingDirective, range: Range) {
  const highlightName = directive.c

  if (CSS.highlights) {
    const existingHighlight = CSS.highlights.get(highlightName)

    if (existingHighlight) {
      existingHighlight.add(range)
      CSS.highlights.set(highlightName, existingHighlight)
    } else {
      const highlight = new Highlight(range)

      CSS.highlights.set(highlightName, highlight)
    }
  } else {
    // else block for eventual polyfill and SSR support
  }
}
