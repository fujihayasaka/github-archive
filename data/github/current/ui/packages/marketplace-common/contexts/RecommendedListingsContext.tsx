import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {IndexPayload, ListingPreview} from '../types'

interface RecommendedListingsContextType {
  recommended: ListingPreview[]
  setRecommended: (recommended: ListingPreview[]) => void
}

const RecommendedListingsContext = createContext<RecommendedListingsContextType | undefined>(undefined)

export function useRecommendedListings() {
  const context = useContext(RecommendedListingsContext)
  if (!context) throw new Error('useRecommendedListings must be used within a RecommendedListingsProvider')
  return context
}

export function RecommendedListingsProvider({children}: PropsWithChildren) {
  const {recommended: initialRecommended} = useRoutePayload<IndexPayload>()
  const [recommended, setRecommended] = useState<ListingPreview[]>(initialRecommended)
  const value = useMemo(() => ({recommended, setRecommended}), [recommended, setRecommended])
  return <RecommendedListingsContext.Provider value={value}>{children}</RecommendedListingsContext.Provider>
}
