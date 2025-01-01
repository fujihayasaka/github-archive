import {createContext, memo, useContext, useMemo} from 'react'

import {useHandlePaginatedDataRefresh} from '../../data-refresh/use-handle-paginated-data-refresh'

type PaginatedMemexItemsQueryContextType = {
  handlePaginatedDataRefresh: ReturnType<typeof useHandlePaginatedDataRefresh>['handleRefresh']
}

const PaginatedMemexItemsQueryContext = createContext<PaginatedMemexItemsQueryContextType | null>(null)

export const PaginatedMemexItemsQueryProvider = memo(function PaginatedMemexItemsQueryProvider({
  children,
}: {
  children: React.ReactNode
}) {
  const {handleRefresh: handlePaginatedDataRefresh} = useHandlePaginatedDataRefresh()

  const value = useMemo(() => {
    return {
      handlePaginatedDataRefresh,
    }
  }, [handlePaginatedDataRefresh])

  return <PaginatedMemexItemsQueryContext.Provider value={value}>{children}</PaginatedMemexItemsQueryContext.Provider>
})

export const usePaginatedMemexItemsQueryContext = () => useContext(PaginatedMemexItemsQueryContext)
