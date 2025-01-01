import {StaticFilterProvider} from '@github-ui/filter/providers'
import {AppsIcon, PlayIcon, AiModelIcon, CopilotIcon, TagIcon} from '@primer/octicons-react'
import type {Category} from '../types'

export const ListingTypeFilterProvider = new StaticFilterProvider(
  {
    key: 'type',
    displayName: 'Listing Type',
    icon: AppsIcon,
    priority: 1,
    description: 'Filter by listing type',
  },
  [
    {
      value: 'copilot',
      description: 'Copilot extensions only',
      priority: 1,
      icon: CopilotIcon,
      displayName: 'Copilot extensions',
    },
    {
      value: 'models',
      description: 'Models only',
      priority: 2,
      icon: AiModelIcon,
      displayName: 'Models',
    },
    {
      value: 'apps',
      description: 'Apps only',
      priority: 3,
      icon: AppsIcon,
      displayName: 'Apps',
    },
    {
      value: 'actions',
      description: 'Actions only',
      priority: 4,
      icon: PlayIcon,
      displayName: 'Actions',
    },
  ],
  {
    filterTypes: {
      exclusive: false,
      multiValue: false,
      multiKey: false,
      valueless: false,
    },
  },
)

/**
 * Creates a StaticFilterProvider for a given set of categories
 * @param categories The options to create the filter provider for
 */
export function createCategoryFilterProvider(categories: Category[]) {
  return new StaticFilterProvider(
    {
      key: 'category',
      displayName: 'Category',
      icon: TagIcon,
      priority: 1,
      description: 'Filter by category or tag',
      aliases: ['tag'],
    },
    categories.map((category, idx) => ({
      value: category.slug,
      displayName: category.name,
      priority: idx + 1,
    })),
    {
      filterTypes: {
        exclusive: false,
        multiKey: false,
        multiValue: false,
        valueless: false,
      },
    },
  )
}
