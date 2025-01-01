import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {IndexPayload, ListingPreview} from '../types'

interface RecentlyAddedListingsContextType {
  recentlyAdded: ListingPreview[]
  setRecentlyAdded: (recentlyAdded: ListingPreview[]) => void
}

const RecentlyAddedListingsContext = createContext<RecentlyAddedListingsContextType | undefined>(undefined)

export function useRecentlyAddedListings() {
  const context = useContext(RecentlyAddedListingsContext)
  if (!context) throw new Error('useRecentlyAddedListings must be used within a RecentlyAddedListingsProvider')
  return context
}

export function RecentlyAddedListingsProvider({children}: PropsWithChildren) {
  const {recentlyAdded: initialRecentlyAdded} = useRoutePayload<IndexPayload>()
  const [recentlyAdded, setRecentlyAdded] = useState<ListingPreview[]>(initialRecentlyAdded)
  const value = useMemo(() => ({recentlyAdded, setRecentlyAdded}), [recentlyAdded, setRecentlyAdded])
  return <RecentlyAddedListingsContext.Provider value={value}>{children}</RecentlyAddedListingsContext.Provider>
}
