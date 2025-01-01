import {useSearchParams} from 'react-router-dom'
import {useMemo} from 'react'

interface UsePaginationOptions {
  pageSize?: number
  paramName?: string
}

interface UsePaginationReturn<T> {
  currentPage: number
  totalPages: number
  paginatedItems: T[]
  navigateToPage: (page: number) => void
  pageSize: number
}

export function usePagination<T>(items: T[], options: UsePaginationOptions = {}): UsePaginationReturn<T> {
  const {pageSize = 20, paramName = 'page'} = options
  const [searchParams, setSearchParams] = useSearchParams()

  const currentPage = Math.max(1, Number(searchParams.get(paramName)) || 1)
  const totalPages = Math.ceil(items.length / pageSize)

  const paginatedItems = useMemo(() => {
    const startIndex = (currentPage - 1) * pageSize
    const endIndex = startIndex + pageSize
    return items.slice(startIndex, endIndex)
  }, [items, currentPage, pageSize])

  // Helper function to update page in URL
  const navigateToPage = (page: number) => {
    const newSearchParams = new URLSearchParams(searchParams)
    newSearchParams.set(paramName, page.toString())
    setSearchParams(newSearchParams)
  }

  return {
    currentPage,
    totalPages,
    paginatedItems,
    navigateToPage,
    pageSize,
  }
}
