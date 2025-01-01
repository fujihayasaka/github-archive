import type React from 'react'
import {createContext, useContext, useState, useCallback, useMemo} from 'react'

export interface Heading {
  id: string
  text: string
  level: 2 | 3
  parentId?: string // For h3s, reference their parent h2
}

interface HeadingContextType {
  headings: Heading[]
  addHeading: (heading: Heading) => void
  clearHeadings: () => void
  setHeadings: (headings: Heading[]) => void
  organizedHeadings: {[key: string]: {h2: Heading; children: Heading[]}}
}

const HeadingContext = createContext<HeadingContextType | undefined>(undefined)

export function HeadingProvider({children}: {children: React.ReactNode}) {
  const [headings, setHeadings] = useState<Heading[]>([])

  // Memoize the organized headings to prevent unnecessary re-renders
  const organizedHeadings = useMemo(() => {
    const result: {[key: string]: {h2: Heading; children: Heading[]}} = {}

    // First pass: collect all h2s
    for (const heading of headings) {
      if (heading.level === 2) {
        result[heading.id] = {h2: heading, children: []}
      }
    }

    // Second pass: assign h3s to their closest preceding h2
    let currentH2Id: string | null = null
    for (const heading of headings) {
      if (heading.level === 2) {
        currentH2Id = heading.id
      } else if (heading.level === 3 && currentH2Id && result[currentH2Id]) {
        result[currentH2Id]?.children.push(heading)
      }
    }

    return result
  }, [headings])

  const addHeading = useCallback((heading: Heading) => {
    setHeadings(prev => {
      // Check if heading already exists
      const exists = prev.some(h => h.id === heading.id)
      if (exists) return prev
      return [...prev, heading]
    })
  }, [])

  const clearHeadings = useCallback(() => {
    setHeadings([])
  }, [])

  const value = useMemo(
    () => ({
      headings,
      addHeading,
      clearHeadings,
      setHeadings,
      organizedHeadings,
    }),
    [headings, addHeading, clearHeadings, organizedHeadings],
  )

  return <HeadingContext.Provider value={value}>{children}</HeadingContext.Provider>
}

export function useHeadings() {
  const context = useContext(HeadingContext)
  if (context === undefined) {
    throw new Error('useHeadings must be used within a HeadingProvider')
  }
  return context
}
