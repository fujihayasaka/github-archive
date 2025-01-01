import isEqual from 'lodash-es/isEqual'
import {useEffect, useMemo, useRef} from 'react'

import type {MemexProjectColumnId} from '../api/columns/contracts/memex-column'
import {filterFalseyValues} from '../helpers/util'
import {useFindColumnByDatabaseId} from '../state-providers/columns/use-find-column-by-database-id'
import type {PaginatedMemexItemsQueryVariables} from '../state-providers/memex-items/queries/types'
import {useNextPlaceholderQuery} from '../state-providers/memex-items/queries/use-next-placeholder-query'
import {useViews} from './use-views'

/*
 * A hook to access the synthetic ids of visible fields for the current view.
 * Used to limit the fields returned in paginated items requests.
 */
export function usePaginatedVariablesWithFieldIds(
  variablesWithoutFieldIds: Omit<PaginatedMemexItemsQueryVariables, 'fieldIds'>,
): PaginatedMemexItemsQueryVariables {
  const {currentView} = useViews()
  const {findColumnByDatabaseId} = useFindColumnByDatabaseId()
  // useViews stores fields for the current view as database ids
  const {visibleFields: visibleFieldIds, layoutSettings, aggregationSettings} = currentView?.localViewState ?? {}
  const {dateFields, markerFields} = layoutSettings?.roadmap ?? {}
  const {sum: aggregationFieldIds} = aggregationSettings ?? {}
  // But the server expects synthetic field ids in the request
  const nextVisibleFieldIds = useMemo(() => {
    const ids = visibleFieldIds
      ?.concat(dateFields?.filter(id => id !== 'none') ?? [])
      .concat(markerFields ?? [])
      .concat(aggregationFieldIds ?? [])
    const filteredIds = filterFalseyValues(ids?.map(databaseId => findColumnByDatabaseId(databaseId)?.id) || [])
    return filteredIds.length === 0 ? undefined : filteredIds.sort()
  }, [visibleFieldIds, dateFields, markerFields, aggregationFieldIds, findColumnByDatabaseId])

  const viewId = currentView?.id ?? -1

  // Store previously visible field IDs by view ID
  // so that we can compare and detect changes
  const visibleFieldIdsRef = useRef({} as Record<number, Array<MemexProjectColumnId> | undefined>)
  if (nextVisibleFieldIds && visibleFieldIdsRef.current[viewId] === undefined) {
    // eslint-disable-next-line react-compiler/react-compiler
    visibleFieldIdsRef.current[viewId] = nextVisibleFieldIds
  }

  const {setUpNextPlaceholderQueries} = useNextPlaceholderQuery(
    {...variablesWithoutFieldIds, fieldIds: nextVisibleFieldIds},
    visibleFieldIdsRef.current[viewId],
  )

  useEffect(() => {
    if (!isEqual(nextVisibleFieldIds, visibleFieldIdsRef.current[viewId])) {
      // Note: when nextVisibleFieldIds changes, this useEffect will be (re)evaluated at
      // each usePaginatedMemexItemsQueryVariables callsite. This is fine, because
      // setUpNextPlaceholderQueries guards against setting up placeholders more than once
      // for the same field ids.
      setUpNextPlaceholderQueries()
      visibleFieldIdsRef.current[viewId] = nextVisibleFieldIds
    }
  }, [nextVisibleFieldIds, viewId, setUpNextPlaceholderQueries])

  // We want to use the fieldIds that are found in the ref
  // as a dependency to the `useMemo`, so that if the fieldIds themselves
  // are changed, we produce a new variables object.
  const fieldIds = visibleFieldIdsRef.current[viewId]

  return useMemo(
    () => ({
      ...variablesWithoutFieldIds,
      fieldIds,
    }),
    [variablesWithoutFieldIds, fieldIds],
  )
}
