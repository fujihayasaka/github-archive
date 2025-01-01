import {useMemo} from 'react'
import {
  AutofilterFilterProvider,
  AutofixFilterProvider,
  CampaignFilterProvider,
  ResolutionFilterProvider,
  SeverityFilterProvider,
  SortFilterProvider,
  StateFilterProvider,
} from '../filter-providers/StaticProviders'
import {
  CustomPropertyFilterProvider,
  RuleFilterProvider,
  RepositoryFilterProvider,
  TeamFilterProvider,
  TopicFilterProvider,
  ToolFilterProvider,
  TagFilterProvider,
} from '../filter-providers/DynamicProviders'
import {
  codeScanningOrgRepositoryListPath,
  codeScanningOrgRuleListPath,
  codeScanningOrgTagListPath,
  codeScanningOrgToolListPath,
  getRelativeHref,
  securityCenterOptionsPath,
} from '@github-ui/paths'

type UseFilterProvidersOptions = {
  organizationLogin: string
  showSort: boolean
  showNewAutofixFilters: boolean
  showCampaignFilter: boolean
  customPropertyNames: string[]
  securityCampaignNumber?: number
}

export function useAlertFilterProviders({
  organizationLogin,
  showSort,
  showNewAutofixFilters,
  showCampaignFilter,
  customPropertyNames,
  securityCampaignNumber,
}: UseFilterProvidersOptions) {
  const filterProviders = useMemo(() => {
    const suggestionsPath = securityCenterOptionsPath({
      org: organizationLogin,
    })

    // Order determines the position of the filter in suggestion list.
    const providers = [
      new RepositoryFilterProvider({
        path: getRelativeHref(
          codeScanningOrgRepositoryListPath,
          {org: organizationLogin},
          {
            security_campaign_number: securityCampaignNumber,
          },
        ).toString(),
      }),
      new ResolutionFilterProvider(),
      new RuleFilterProvider({
        path: getRelativeHref(
          codeScanningOrgRuleListPath,
          {org: organizationLogin},
          {
            security_campaign_number: securityCampaignNumber,
          },
        ).toString(),
      }),
      new TagFilterProvider({
        path: getRelativeHref(
          codeScanningOrgTagListPath,
          {org: organizationLogin},
          {
            security_campaign_number: securityCampaignNumber,
          },
        ).toString(),
      }),
      new SeverityFilterProvider(),
      ...(showSort ? [new SortFilterProvider()] : []),
      new StateFilterProvider(),
      new TeamFilterProvider({path: suggestionsPath}),
      new ToolFilterProvider({
        path: getRelativeHref(
          codeScanningOrgToolListPath,
          {org: organizationLogin},
          {
            security_campaign_number: securityCampaignNumber,
          },
        ).toString(),
      }),
      new TopicFilterProvider({path: suggestionsPath}),
      new AutofilterFilterProvider(),
      new AutofixFilterProvider(showNewAutofixFilters),
      ...customPropertyNames.map(
        name => new CustomPropertyFilterProvider({customPropertyName: name, path: suggestionsPath}),
      ),
    ]

    if (showCampaignFilter) {
      providers.push(new CampaignFilterProvider())
    }

    return providers
  }, [
    organizationLogin,
    showSort,
    showNewAutofixFilters,
    customPropertyNames,
    securityCampaignNumber,
    showCampaignFilter,
  ])

  return filterProviders
}
