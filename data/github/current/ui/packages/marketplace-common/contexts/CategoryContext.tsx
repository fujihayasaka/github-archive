import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import {getDefaultCategory as getModelsDefaultCategory} from '../utilities/model-filter-options'
import {useSearchResults} from './SearchResultsContext'

interface CategoryContextType {
  category: string | null
  setCategory: (category: string | null) => void
}

const CategoryContext = createContext<CategoryContextType | undefined>(undefined)

export function useCategory() {
  const context = useContext(CategoryContext)
  if (!context) throw new Error('useCategory must be used within a CategoryProvider')
  return context
}

export function CategoryProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const {searchResults} = useSearchResults()

  // We should ensure that users can't put arbitrary strings in the URL and have them displayed in the search
  // dropdowns. Since category is shared between listing types, we can only validate it against the allowlist
  // if type === model.
  const initialCategory = useMemo(() => {
    if (searchParams.get('type') === 'models') {
      return getModelsDefaultCategory(searchParams, searchResults.parsedQuery)
    }
    if (searchParams.has('type')) return searchParams.get('category')
    return null
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const [category, setCategory] = useState<string | null>(initialCategory)
  const value = useMemo(() => ({category, setCategory}), [category, setCategory])
  return <CategoryContext.Provider value={value}>{children}</CategoryContext.Provider>
}
