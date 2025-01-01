import {useEffect} from 'react'
import type {StylingDirectivesLine} from '../types'
import {addHighlight} from '../utils/highlight'
import {createRange} from '../utils/range'

export function useHighlight(ref: React.RefObject<HTMLDivElement>, styleDirectives: StylingDirectivesLine | undefined) {
  useEffect(() => {
    if (!ref.current || !styleDirectives) return

    for (const directive of styleDirectives) {
      const range = createRange(ref.current, directive.s, directive.e)

      if (!range) continue

      addHighlight(directive, range)
    }
  }, [ref, styleDirectives])
}
