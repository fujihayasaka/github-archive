import type {FilterProvider} from '@github-ui/filter'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
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
  SecretBypassedFilterProvider,
  SecretValidityFilterProvider,
  SeverityFilterProvider,
  VisibilityFilterProvider,
} from '../common/filter-providers/StaticProviders'
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
  const payload = useRoutePayload<OverviewPayload>()
  const {business} = useParams()

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
    ]

    if (business != null) {
      providers.push(new OwnerFilterProvider(paths))
      if (payload.allowOwnerTypeFiltering) {
        providers.push(new OwnerTypeFilterProvider())
      }
    }

    return providers
  }, [payload.customProperties, payload.allowOwnerTypeFiltering, paths, business])

  return (
    <PathsContext.Provider value={paths}>
      <SecurityCenterOverviewDashboard {...payload} filterProviders={filterProviders} />
    </PathsContext.Provider>
  )
}
