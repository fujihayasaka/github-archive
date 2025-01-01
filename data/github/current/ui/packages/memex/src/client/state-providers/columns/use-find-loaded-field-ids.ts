import {useCallback} from 'react'

import type {SystemColumnId} from '../../api/columns/contracts/memex-column'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {useViews} from '../../hooks/use-views'
import {useColumnsStableContext} from './use-columns-stable-context'

type FindLoadedFieldIdsHookReturnType = {
  /**
   * Queries the client-side state to determine which columns have been loaded
   * (i.e. we have column values for)
   * @return A list of column ids which have been loaded
   */
  findLoadedFieldIds: () => ReadonlyArray<SystemColumnId | number>
}

export const useFindLoadedFieldIds = (): FindLoadedFieldIdsHookReturnType => {
  const {loadedFieldIdsRef} = useColumnsStableContext()
  const findLoadedFieldIds = useCallback(() => {
    return [...loadedFieldIdsRef.current]
  }, [loadedFieldIdsRef])

  return {findLoadedFieldIds}
}

export const useFindLoadedFieldIdsForCurrentView = (): FindLoadedFieldIdsHookReturnType => {
  const {loadedFieldIdsRef: loadedFieldIdsForViewRef, currentView} = useViews()
  const {memex_table_without_limits} = useEnabledFeatures()

  const {findLoadedFieldIds: findLoadedFieldIdsForProject} = useFindLoadedFieldIds()

  // When PWL is enabled, field load state is tracked per view
  const useFindLoadedFieldIdsForView = useCallback(() => {
    return [...(loadedFieldIdsForViewRef.current[currentView?.id ?? -1] ?? [])]
  }, [loadedFieldIdsForViewRef, currentView?.id])

  return {
    findLoadedFieldIds: memex_table_without_limits ? useFindLoadedFieldIdsForView : findLoadedFieldIdsForProject,
  }
}
