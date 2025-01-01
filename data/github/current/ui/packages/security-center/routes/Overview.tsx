import type {FilterProvider} from '@github-ui/filter'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {QueryClientProvider} from '@tanstack/react-query'
import {useMemo} from 'react'
import {useParams} from 'react-router-dom'

import {EnterprisePaths, OrgPaths, type Paths, PathsContext} from '../common/contexts/Paths'
import {
  CodeQLRuleFilterProvider,
  createCustomPropertyFilterProviders,
  DependabotEcosystemFilterProvider,
  DependabotPackageFilterProvider,
  OwnerFilterProvider,
  RepositoryFilterProvider,
  SecretProviderFilterProvider,
  SecretTypeFilterProvider,
  TeamFilterProvider,
  ThirdPartyRuleFilterProvider,
  ToolFilterProvider,
  TopicFilterProvider,
} from '../common/filter-providers/DynamicProviders'
import {
  ArchivedFilterProvider,
  DependabotScopeFilterProvider,
  OwnerTypeFilterProvider,
  ResolutionFilterProvider,
  SecretBypassedFilterProvider,
  SecretValidityFilterProvider,
  SeverityFilterProvider,
  VisibilityFilterProvider,
} from '../common/filter-providers/StaticProviders'
import {createQueryClient} from '../common/utils/query-client'
import {
  SecurityCenterOverviewDashboard,
  type SecurityCenterOverviewDashboardProps,
} from '../overview-dashboard/SecurityCenterOverviewDashboard'

export interface OverviewPayload extends SecurityCenterOverviewDashboardProps {}

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

export function Overview(): JSX.Element {
  const paths = usePaths()
  const queryClient = createQueryClient()
  const payload = useRoutePayload<OverviewPayload>()
  const {business} = useParams()
  const showResolutionFilter = useFeatureFlag('security_center_dashboards_show_resolution_filter')

  const filterProviders = useMemo((): FilterProvider[] => {
    const customProperties = payload.customProperties

    const providers = [
      new RepositoryFilterProvider(paths),
      new ToolFilterProvider(paths),
      new TopicFilterProvider(paths),
      new TeamFilterProvider(paths),
      new VisibilityFilterProvider(),
      new ArchivedFilterProvider(),
      new DependabotEcosystemFilterProvider(paths),
      new DependabotPackageFilterProvider(paths),
      new DependabotScopeFilterProvider(),
      new CodeQLRuleFilterProvider(paths),
      new ThirdPartyRuleFilterProvider(paths),
      new SecretTypeFilterProvider(paths),
      new SecretProviderFilterProvider(paths),
      new SecretValidityFilterProvider(),
      new SecretBypassedFilterProvider(),
      ...createCustomPropertyFilterProviders(paths, customProperties),
      new SeverityFilterProvider(),
      ...(showResolutionFilter ? [new ResolutionFilterProvider()] : []),
    ]

    if (business != null) {
      providers.push(new OwnerFilterProvider(paths))
      if (payload.allowOwnerTypeFiltering) {
        providers.push(new OwnerTypeFilterProvider())
      }
    }

    return providers
  }, [payload.customProperties, showResolutionFilter, payload.allowOwnerTypeFiltering, paths, business])

  return (
    <PathsContext.Provider value={paths}>
      <QueryClientProvider client={queryClient}>
        <SecurityCenterOverviewDashboard {...payload} filterProviders={filterProviders} />
      </QueryClientProvider>
    </PathsContext.Provider>
  )
}
