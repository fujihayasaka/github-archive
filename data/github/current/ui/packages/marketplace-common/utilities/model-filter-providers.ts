import {StaticFilterProvider} from '@github-ui/filter/providers'
import {CpuIcon, InboxIcon, LawIcon, RocketIcon, SignOutIcon, TagIcon, TypographyIcon} from '@primer/octicons-react'
import {
  allCategoriesOptionID,
  allPublishersOption,
  allTasksOptionID,
  categoryOptions,
  inputModalityOptions,
  languageOptions,
  licenseOptions,
  publisherOptions,
  outputModalityOptions,
  taskOptions,
} from './model-filter-options'

export const ModelsCategoryFilterProvider = new StaticFilterProvider(
  {
    key: 'category',
    displayName: 'Category',
    priority: 1,
    icon: TagIcon,
    description: 'Filter by category or tag',
    aliases: ['tag'],
  },
  categoryOptions
    .filter(option => option.id !== allCategoriesOptionID)
    .map(({id, name}, index) => ({value: id, displayName: name, priority: index + 1})),
  {
    // https://ui.githubapp.com/storybook/?path=/docs/recipes-filter-providers-standard--docs#filtertypes
    filterTypes: {exclusive: false, multiKey: false},
  },
)

export const ModelsPublisherFilterProvider = new StaticFilterProvider(
  {
    key: 'publisher',
    displayName: 'Publisher',
    priority: 1,
    icon: CpuIcon,
    description: 'Filter by publisher',
    aliases: [],
  },
  publisherOptions
    .filter(publisher => publisher !== allPublishersOption)
    .map((publisher, index) => ({value: publisher, displayName: publisher, priority: index + 1})),
  {
    // https://ui.githubapp.com/storybook/?path=/docs/recipes-filter-providers-standard--docs#filtertypes
    filterTypes: {exclusive: false, multiValue: false},
  },
)

export const ModelsInputModalityFilterProvider = new StaticFilterProvider(
  {
    key: 'input-modality',
    displayName: 'Input modality',
    priority: 1,
    icon: InboxIcon,
    description: 'Filter by supported input modality',
    aliases: [],
  },
  inputModalityOptions.map((modality, index) => ({
    value: modality,
    displayName: modality,
    priority: index + 1,
  })),
  {
    // https://ui.githubapp.com/storybook/?path=/docs/recipes-filter-providers-standard--docs#filtertypes
    filterTypes: {exclusive: false},
  },
)

export const ModelsLanguageFilterProvider = new StaticFilterProvider(
  {
    key: 'language',
    displayName: 'Supported language',
    priority: 1,
    icon: TypographyIcon,
    description: 'Filter by supported language',
    aliases: [],
  },
  languageOptions.map(({id, name}, index) => ({
    value: id,
    displayName: name,
    priority: index + 1,
  })),
  {
    // https://ui.githubapp.com/storybook/?path=/docs/recipes-filter-providers-standard--docs#filtertypes
    filterTypes: {exclusive: false},
  },
)

export const ModelsLicenseFilterProvider = new StaticFilterProvider(
  {
    key: 'license',
    displayName: 'License',
    priority: 1,
    icon: LawIcon,
    description: 'Filter by license type',
    aliases: [],
  },
  licenseOptions.map(({id, name}, index) => ({
    value: id,
    displayName: name,
    priority: index + 1,
  })),
  {
    // https://ui.githubapp.com/storybook/?path=/docs/recipes-filter-providers-standard--docs#filtertypes
    filterTypes: {exclusive: false, multiValue: false},
  },
)

export const ModelsOutputModalityFilterProvider = new StaticFilterProvider(
  {
    key: 'output-modality',
    displayName: 'Output modality',
    priority: 1,
    icon: SignOutIcon,
    description: 'Filter by supported output modality',
    aliases: [],
  },
  outputModalityOptions.map((modality, index) => ({
    value: modality,
    displayName: modality,
    priority: index + 1,
  })),
  {
    // https://ui.githubapp.com/storybook/?path=/docs/recipes-filter-providers-standard--docs#filtertypes
    filterTypes: {exclusive: false},
  },
)

export const ModelsTaskFilterProvider = new StaticFilterProvider(
  {
    key: 'task',
    displayName: 'Capability',
    priority: 1,
    icon: RocketIcon,
    description: 'Filter by model capability',
    aliases: [],
  },
  taskOptions
    .filter(option => option.id !== allTasksOptionID)
    .map(({id, name}, index) => ({
      value: id,
      priority: index + 1,
      displayName: name,
    })),
  {
    // https://ui.githubapp.com/storybook/?path=/docs/recipes-filter-providers-standard--docs#filtertypes
    filterTypes: {exclusive: false, multiValue: false},
  },
)
