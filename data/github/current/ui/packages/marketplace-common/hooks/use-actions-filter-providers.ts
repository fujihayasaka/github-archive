import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {IndexPayload} from '../types'
import {useMemo} from 'react'
import {createCategoryFilterProvider} from '../utilities/filter-providers'

export default function useActionsFilterProviders() {
  const {
    categories: {actions},
  } = useRoutePayload<IndexPayload>()

  const AppsCategoryFilterProvider = useMemo(() => {
    return createCategoryFilterProvider(actions)
  }, [actions])

  return [AppsCategoryFilterProvider]
}
