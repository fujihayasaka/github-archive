import {useEffect} from 'react'
import type {StylingDirectivesLine} from '../types'
import {addHighlight} from '../utils/highlight'
import {createRange} from '../utils/range'
import {parseDirectives} from '../ast-utils/parse-node'

export function useHighlight(ref: React.RefObject<HTMLDivElement>, styleDirectives: StylingDirectivesLine | undefined) {
  useEffect(() => {
    if (!ref.current || !styleDirectives) return

    const normalizedDirectives = parseDirectives(styleDirectives ?? [])

    for (const directive of normalizedDirectives) {
      const range = createRange(ref.current, directive.s, directive.e)

      if (!range) continue

      addHighlight(directive, range)
    }
  }, [ref, styleDirectives])
}
