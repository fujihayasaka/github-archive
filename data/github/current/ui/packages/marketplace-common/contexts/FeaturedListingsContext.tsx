import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {IndexPayload, ListingPreview} from '../types'

interface FeaturedListingsContextType {
  featured: ListingPreview[]
  setFeatured: (featured: ListingPreview[]) => void
}

const FeaturedListingsContext = createContext<FeaturedListingsContextType | undefined>(undefined)

export function useFeaturedListings() {
  const context = useContext(FeaturedListingsContext)
  if (!context) throw new Error('useFeaturedListings must be used within a FeaturedListingsProvider')
  return context
}

export function FeaturedListingsProvider({children}: PropsWithChildren) {
  const {featured: initialFeatured} = useRoutePayload<IndexPayload>()
  const [featured, setFeatured] = useState<ListingPreview[]>(initialFeatured)
  const value = useMemo(() => ({featured, setFeatured}), [featured, setFeatured])
  return <FeaturedListingsContext.Provider value={value}>{children}</FeaturedListingsContext.Provider>
}
