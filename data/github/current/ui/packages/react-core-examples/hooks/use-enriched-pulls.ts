import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {useMemo} from 'react'

import {reactCoreExamplesEnrichedDataRoute} from '../routes/enriched-data-route'

export function useEnrichedPulls(showErrorState = false) {
  const {
    data: {pulls},
  } = useRouteQuery(reactCoreExamplesEnrichedDataRoute, 'mainQuery')
  const {
    data: deferredData,
    isPending,
    isError,
    refetch,
  } = useRouteQuery(reactCoreExamplesEnrichedDataRoute, showErrorState ? 'badQuery' : 'enrichedPulls')

  const enrichedPulls = useMemo(() => {
    return pulls.map(pull => {
      const deferredPull = deferredData?.pulls.find(deferredPullData => deferredPullData.id === pull.id)
      return {
        ...pull,
        labels: deferredPull?.labels,
      }
    })
  }, [deferredData?.pulls, pulls])

  return {
    pulls: enrichedPulls,
    isPending,
    isError,
    refetch,
  }
}
