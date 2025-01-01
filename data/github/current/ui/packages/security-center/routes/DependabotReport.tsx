import type {FilterProvider} from '@github-ui/filter'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useMemo} from 'react'
import {useParams} from 'react-router-dom'

import {EnterprisePaths, OrgPaths, type Paths, PathsContext} from '../common/contexts/Paths'
import {
  ArchivedFilterProvider,
  createCustomPropertyFilterProviders,
  DependabotEpssPercentageFilterProvider,
  DependabotRelationshipFilterProvider,
  DependabotUnlabeledEcosystemFilterProvider,
  DependabotUnlabeledPackageFilterProvider,
  DependabotUnlabeledScopeFilterProvider,
  OwnerFilterProvider,
  RepositoryFilterProvider,
  SeverityFilterProvider,
  StateFilterProvider,
  TeamFilterProvider,
  TopicFilterProvider,
  VisibilityFilterProvider,
} from '../common/filter-providers'
import type {CustomProperty} from '../common/filter-providers/types'
import {
  SecurityCenterDependabotMetrics,
  type SecurityCenterDependabotMetricsProps,
} from '../dependabot-report/SecurityCenterDependabotMetrics'

export interface DependabotReportPayload extends SecurityCenterDependabotMetricsProps {
  customProperties?: CustomProperty[]
}

function usePaths(): Paths {
  const {org, business} = useParams()
  const paths = useMemo(() => {
    if (org != null) {
      return new OrgPaths(org)
    } else if (business != null) {
      return new EnterprisePaths(business)
    }
  }, [org, business])

  if (paths == null) {
    throw new Error('Failed to parse path params from current location')
  }

  return paths
}

export function useFilterProviders(paths: Paths, customProperties?: CustomProperty[]): FilterProvider[] {
  return useMemo(() => {
    // Order determins the position of the filter in suggestion list.
    const providers: FilterProvider[] = [
      new RepositoryFilterProvider(paths),
      new TopicFilterProvider(paths),
      new TeamFilterProvider(paths),
      new VisibilityFilterProvider(),
      new ArchivedFilterProvider(),
      new StateFilterProvider(),
      new SeverityFilterProvider(),
      new DependabotUnlabeledScopeFilterProvider(),
      new DependabotUnlabeledPackageFilterProvider(paths),
      new DependabotUnlabeledEcosystemFilterProvider(paths),
      new DependabotRelationshipFilterProvider(),
      new DependabotEpssPercentageFilterProvider(),
      ...createCustomPropertyFilterProviders(paths, customProperties || []),
    ]

    if (paths instanceof EnterprisePaths) {
      // Filters that only apply to enterprise-scope experience
      providers.push(new OwnerFilterProvider(paths))
    }

    return providers
  }, [paths, customProperties])
}

export function DependabotReport(): JSX.Element {
  const paths = usePaths()
  const routePayload = useRoutePayload<DependabotReportPayload>()

  const filterProviders = useFilterProviders(paths, routePayload.customProperties)

  const payload = {
    ...routePayload,
    filterProviders,
  }
  return (
    <PathsContext.Provider value={paths}>
      <SecurityCenterDependabotMetrics {...payload} />
    </PathsContext.Provider>
  )
}
