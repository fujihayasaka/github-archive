import {CodescanIcon, PeopleIcon, RepoIcon, TagIcon, ToolsIcon} from '@primer/octicons-react'
import AsyncSuggestionsFilterProvider from './AsyncSuggestionsFilterProvider'
import type {FilterKey} from '@github-ui/filter'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

export class RepositoryFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path, securityCampaignNumber}: {path: string; securityCampaignNumber: number}) {
    super(
      {
        displayName: 'Repository',
        key: 'repo',
        priority: 1,
        icon: RepoIcon,
        description: 'Find alerts for the selected repositories',
      } as FilterKey,
      urlWithSecurityCampaignNumber({path, securityCampaignNumber}),
    )
  }
}

export class TeamFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path}: {path: string}) {
    super(
      {
        displayName: 'Team',
        key: 'team',
        priority: 1,
        icon: PeopleIcon,
        description: 'Find alerts for repositories the selected teams can access',
      } as FilterKey,
      getSuggestionsPath({path, type: 'teams'}),
    )
  }
}

export class TopicFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path}: {path: string}) {
    super(
      {
        displayName: 'Topic',
        key: 'topic',
        priority: 1,
        icon: TagIcon,
        description: 'Find alerts for repositories with the selected topics',
      } as FilterKey,
      getSuggestionsPath({path, type: 'topics'}),
    )
  }
}

export class RuleFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path, securityCampaignNumber}: {path: string; securityCampaignNumber: number}) {
    super(
      {
        displayName: 'Rule',
        key: 'rule',
        priority: 1,
        icon: CodescanIcon,
        description: 'Find alerts from the selected rule',
      } as FilterKey,
      urlWithSecurityCampaignNumber({path, securityCampaignNumber}),
    )
  }
}

export class TagFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path, securityCampaignNumber}: {path: string; securityCampaignNumber: number}) {
    super(
      {
        displayName: 'Rule tag',
        key: 'tag',
        priority: 1,
        icon: TagIcon,
        description: 'Find alerts from the selected rule tag',
      } as FilterKey,
      urlWithSecurityCampaignNumber({path, securityCampaignNumber}),
    )
  }
}

export class ToolFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path, securityCampaignNumber}: {path: string; securityCampaignNumber: number}) {
    super(
      {
        displayName: 'Tool',
        key: 'tool',
        priority: 1,
        icon: ToolsIcon,
        description: 'Find alerts from the selected tool',
      } as FilterKey,
      urlWithSecurityCampaignNumber({path, securityCampaignNumber}),
    )
  }
}

function getSuggestionsPath({path, type}: {path: string; type: string}): string {
  const url = new URL(path, ssrSafeLocation.origin)
  url.searchParams.set('options-type', type)
  return url.toString()
}

function urlWithSecurityCampaignNumber({path, securityCampaignNumber}: {path: string; securityCampaignNumber: number}) {
  const url = new URL(path, ssrSafeLocation.origin)
  url.searchParams.set('security_campaign_number', securityCampaignNumber.toString())
  return url.toString()
}
