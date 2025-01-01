import {useMemo} from 'react'
import {
  AutofilterFilterProvider,
  AutofixFilterProvider,
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
  showNewAutofixFilters: boolean
  customPropertyNames: string[]
  securityCampaignNumber?: number
}

export function useAlertFilterProviders({
  organizationLogin,
  showNewAutofixFilters,
  customPropertyNames,
  securityCampaignNumber,
}: UseFilterProvidersOptions) {
  const filterProviders = useMemo(() => {
    const suggestionsPath = securityCenterOptionsPath({
      org: organizationLogin,
    })

    // Order determines the position of the filter in suggestion list.
    return [
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
      new SortFilterProvider(),
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
  }, [organizationLogin, showNewAutofixFilters, customPropertyNames, securityCampaignNumber])

  return filterProviders
}
