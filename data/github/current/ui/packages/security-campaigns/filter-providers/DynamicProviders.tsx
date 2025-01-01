import {CodescanIcon, NoteIcon, PeopleIcon, RepoIcon, TagIcon, ToolsIcon} from '@primer/octicons-react'
import AsyncSuggestionsFilterProvider from './AsyncSuggestionsFilterProvider'
import type {FilterKey} from '@github-ui/filter'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

export class RepositoryFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path}: {path: string}) {
    super(
      {
        displayName: 'Repository',
        key: 'repo',
        priority: 1,
        icon: RepoIcon,
        description: 'Find alerts for the selected repositories',
      } as FilterKey,
      path,
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
  constructor({path}: {path: string}) {
    super(
      {
        displayName: 'Rule',
        key: 'rule',
        priority: 1,
        icon: CodescanIcon,
        description: 'Find alerts from the selected rule',
      } as FilterKey,
      path,
    )
  }
}

export class TagFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path}: {path: string}) {
    super(
      {
        displayName: 'Rule tag',
        key: 'tag',
        priority: 1,
        icon: TagIcon,
        description: 'Find alerts from the selected rule tag',
      } as FilterKey,
      path,
    )
  }
}

export class ToolFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({path}: {path: string}) {
    super(
      {
        displayName: 'Tool',
        key: 'tool',
        priority: 1,
        icon: ToolsIcon,
        description: 'Find alerts from the selected tool',
      } as FilterKey,
      path,
    )
  }
}

export class CustomPropertyFilterProvider extends AsyncSuggestionsFilterProvider {
  constructor({customPropertyName, path}: {customPropertyName: string; path: string}) {
    super(
      {
        displayName: `Custom property: ${customPropertyName}`,
        key: `props.${customPropertyName}`,
        priority: 1,
        icon: NoteIcon,
        description: `Custom property: ${customPropertyName}`,
      } as FilterKey,
      getSuggestionsPath(
        {path, type: 'props'},
        {
          name: customPropertyName,
        },
      ),
    )
  }
}

function getSuggestionsPath(
  {path, type}: {path: string; type: string},
  additionalParams: Record<string, string> = {},
): string {
  const url = new URL(path, ssrSafeLocation.origin)
  url.searchParams.set('options-type', type)
  for (const [key, value] of Object.entries(additionalParams)) {
    url.searchParams.set(key, value)
  }
  return url.toString()
}
