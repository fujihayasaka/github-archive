import {PeopleIcon} from '@primer/octicons-react'
import {StaticFilterProvider} from '@github-ui/filter/providers'
import {IS_KEY, SelectedTab} from '../types/selected-tab'
import type {FilterKey, FilterSuggestion, SuppliedFilterProviderOptions} from '@github-ui/filter'
import {FilterQueryParser} from '@github-ui/filter/parser'
import {isFilterBlock} from '@github-ui/filter/utils'

class AssigneeTypeFilterProvider extends StaticFilterProvider {
  constructor() {
    const filterKey: FilterKey = {
      displayName: 'Assignee type',
      key: IS_KEY,
      priority: 1,
      icon: PeopleIcon,
      description: 'Filter by assignee type. Default: user',
    }

    const filterSuggestions: FilterSuggestion[] = [
      {value: SelectedTab.User, displayName: 'User', priority: 1},
      {value: SelectedTab.Team, displayName: 'Team', priority: 2},
    ]

    const filterOptions: SuppliedFilterProviderOptions = {
      filterTypes: {multiKey: false, multiValue: false, valueless: false, exclusive: false},
    }

    super(filterKey, filterSuggestions, filterOptions)
  }
}

const assigneeTypeFilterProvider = new AssigneeTypeFilterProvider()
export const assignmentFilterProviders = [assigneeTypeFilterProvider]

// returns true if there is a search query other than `is` filter
export function hasNonAssigneeSearchQuery(query: string): boolean {
  if (!query.trim()) {
    return false
  }

  const filterQueryParser = new FilterQueryParser(assignmentFilterProviders)
  const parsedQuery = filterQueryParser.parse(query)

  return parsedQuery.blocks.some(b => !(isFilterBlock(b) && b.key.value === IS_KEY))
}
