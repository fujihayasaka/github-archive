import {useCallback, useEffect, useRef, useState, type KeyboardEvent, type MouseEvent, type PointerEvent} from 'react'
import {getFootnoteId, getFootnoteNumberFromId, isFootnoteId} from '../utils/footnotes'
import {checkPrefersReducedMotion} from '../../../lib/utils/platform'

export interface FootnoteMethods {
  onFootnoteClick: (number: number, event: MouseEvent) => void
  onFootnoteEnter: (number: number, event: PointerEvent) => void
  onFootnoteKeyDown: (number: number, event: KeyboardEvent) => void
}

const useFootnotes = () => {
  const [footnoteStates, setFootnoteStates] = useState<Record<string, boolean>>({})
  const footnoteStatesRef = useRef<Record<string, boolean>>(footnoteStates)
  const isReady = useRef<boolean>(false)
  const isClicking = useRef<boolean>(false)
  const clickTimeoutRef = useRef<NodeJS.Timeout | null>(null)
  const scrollTimeoutRef = useRef<NodeJS.Timeout | null>(null)

  const setHash = useCallback((number: number) => {
    const hash = `#${getFootnoteId(number)}`
    if (window.location.hash === hash) return
    window.location.hash = hash
  }, [])

  const toggleFootnote = useCallback(
    (number: number) => {
      const newState = !footnoteStatesRef.current[String(number)]
      if (newState) setHash(number)
      setFootnoteStates({...footnoteStatesRef.current, [String(number)]: newState})
    },
    [setHash],
  )

  const openFootnote = useCallback(
    (number: number) => {
      if (footnoteStatesRef.current[String(number)]) return

      setHash(number)
      setFootnoteStates({...footnoteStatesRef.current, [String(number)]: true})
    },
    [setHash],
  )

  const onFootnoteClick: FootnoteMethods['onFootnoteClick'] = useCallback(
    number => {
      if (isClicking.current) return
      isClicking.current = true

      if (clickTimeoutRef.current) clearTimeout(clickTimeoutRef.current)
      clickTimeoutRef.current = setTimeout(() => {
        clickTimeoutRef.current = null
        isClicking.current = false
      }, 200)

      toggleFootnote(number)
    },
    [toggleFootnote],
  )

  const onFootnoteEnter: FootnoteMethods['onFootnoteEnter'] = useCallback(
    number => {
      if ('ontouchstart' in window || isClicking.current) return
      openFootnote(number)
    },
    [openFootnote],
  )

  const onFootnoteKeyDown: FootnoteMethods['onFootnoteKeyDown'] = useCallback(
    (number, event) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.key === 'Enter') {
        event.preventDefault()
        toggleFootnote(number)
      }
    },
    [toggleFootnote],
  )

  const onHashChange = useCallback(
    (shouldScrollToFootnote = false) => {
      const hash = window.location.hash?.slice(1)
      if (!isFootnoteId(hash)) return

      const parsedNumber = getFootnoteNumberFromId(hash)
      if (!Number.isFinite(parsedNumber) || !Object.keys(footnoteStatesRef.current).includes(String(parsedNumber)))
        return

      openFootnote(parsedNumber)

      if (scrollTimeoutRef.current) clearTimeout(scrollTimeoutRef.current)
      scrollTimeoutRef.current = setTimeout(() => {
        scrollTimeoutRef.current = null

        if (shouldScrollToFootnote) {
          const element = document.querySelector(`[aria-controls="${hash}"]`)
          if (element) element.scrollIntoView({behavior: checkPrefersReducedMotion() ? 'auto' : 'smooth'})
        }
      }, 500)
    },
    [openFootnote],
  )

  const initFootnotes = useCallback(
    (numbers: number[]) => {
      if (isReady.current) return

      // Set the footnote keys for reference
      for (const number of numbers) {
        footnoteStatesRef.current = {...footnoteStatesRef.current, [String(number)]: false}
      }

      isReady.current = true
      onHashChange(true)
    },
    [onHashChange],
  )

  useEffect(() => {
    if (!isReady.current) {
      // Keep the initial keys references until the footnotes are initialised
      footnoteStatesRef.current = {...footnoteStatesRef.current, ...footnoteStates}
    } else {
      footnoteStatesRef.current = footnoteStates
    }
  }, [footnoteStates])

  useEffect(() => {
    const handleHashChange = () => onHashChange()
    window.addEventListener('hashchange', handleHashChange)

    return () => {
      if (clickTimeoutRef.current) clearTimeout(clickTimeoutRef.current)
      if (scrollTimeoutRef.current) clearTimeout(scrollTimeoutRef.current)
      window.removeEventListener('hashchange', handleHashChange)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {footnoteStates, initFootnotes, onFootnoteClick, onFootnoteEnter, onFootnoteKeyDown}
}

export default useFootnotes
