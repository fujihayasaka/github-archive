import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {IndexPayload} from '../types'
import {useMemo} from 'react'
import {createCategoryFilterProvider} from '../utilities/filter-providers'

export default function useAppsFilterProviders() {
  const {
    categories: {apps},
  } = useRoutePayload<IndexPayload>()

  const AppsCategoryFilterProvider = useMemo(() => {
    return createCategoryFilterProvider(apps)
  }, [apps])

  return [AppsCategoryFilterProvider]
}
