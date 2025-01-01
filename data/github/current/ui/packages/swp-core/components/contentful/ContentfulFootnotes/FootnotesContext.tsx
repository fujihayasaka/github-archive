import type React from 'react'
import {createContext, useCallback, useContext, useMemo, useState} from 'react'
import type {InlineFootnote} from '../../../schemas/contentful/contentTypes/inlineFootnote'

type FootnotesContextType = {
  footnotes: InlineFootnote[]
  registerFootnote: (footnote: InlineFootnote, uniqueId: string) => void
  getFootnoteIndex: (id: string) => number
  getNthInstanceOfFootnote: (id: string, uniqueId: string) => number
  lastClickedReferenceIds: Record<string, string>
  setLastClickedReferenceId: (anchorId: string, id: string) => void
}

const FootnotesContext = createContext<FootnotesContextType | undefined>(undefined)

export const FootnotesProvider: React.FC<{children: React.ReactNode}> = ({children}) => {
  /**
   * Represents the list of all unique footnotes added to the page.
   * This is deduplicated by `sys.id` and determines the order of footnotes rendered at the bottom.
   */
  const [footnotes, setFootnotes] = useState<InlineFootnote[]>([])

  /**
   * Tracks each unique instance of a given footnote. The key is the `sys.id`,
   * and the value is an array of instance-level unique IDs (e.g., from `useId`).
   *
   * This is used to calculate the "nth" occurrence of a footnote, so we can track duplicate footnotes
   */
  const [footnoteInstanceMap, setFootnoteInstanceMap] = useState<Record<string, string[]>>({})

  /**
   * Tracks the most recently clicked inline footnote per `anchorId`.
   * This is used to determine which inline footnote should be scrolled to
   * when the user clicks the return link at the bottom of the page.
   */
  const [lastClickedReferenceIds, setLastClickedReferenceIds] = useState<Record<string, string>>({})

  const registerFootnote = useCallback((footnote: InlineFootnote, uniqueId: string) => {
    const footnoteId = footnote.sys.id

    setFootnotes(prev => {
      if (prev.some(f => f.sys.id === footnote.sys.id)) return prev
      return [...prev, footnote]
    })

    setFootnoteInstanceMap(prev => {
      const existing = prev[footnoteId] || []
      if (existing.includes(uniqueId)) return prev

      return {
        ...prev,
        [footnoteId]: [...existing, uniqueId],
      }
    })
  }, [])

  const setLastClickedReferenceId = useCallback((anchorId: string, id: string) => {
    setLastClickedReferenceIds(prev => ({...prev, [anchorId]: id}))
  }, [])

  const getNthInstanceOfFootnote = useCallback(
    (footnoteId: string, uniqueId: string) => {
      const instances = footnoteInstanceMap[footnoteId] || []
      return instances.indexOf(uniqueId)
    },
    [footnoteInstanceMap],
  )

  const getFootnoteIndex = useCallback(
    (id: string) => {
      return footnotes.findIndex(f => f.sys.id === id)
    },
    [footnotes],
  )

  const value = useMemo(
    () => ({
      footnotes,
      registerFootnote,
      getFootnoteIndex,
      getNthInstanceOfFootnote,
      lastClickedReferenceIds,
      setLastClickedReferenceId,
    }),
    [
      footnotes,
      registerFootnote,
      getFootnoteIndex,
      getNthInstanceOfFootnote,
      lastClickedReferenceIds,
      setLastClickedReferenceId,
    ],
  )
  return <FootnotesContext.Provider value={value}>{children}</FootnotesContext.Provider>
}

export const useFootnotes = () => {
  return useContext(FootnotesContext)
}
