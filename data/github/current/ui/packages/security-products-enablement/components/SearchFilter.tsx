import {Filter, type FilterKey, type FilterQuery, type FilterSuggestion} from '@github-ui/filter'
import {LanguageFilterProvider} from '@github-ui/filter/providers'
import {
  getAllStaticProviders,
  getCustomPropertiesProvider,
  type PropertyDefinition,
} from '@github-ui/repos-filter/providers'
import {PeopleIcon, TasklistIcon} from '@primer/octicons-react'
import {TeamFilterProvider} from './Team'
import {useAppContext} from '../contexts/AppContext'
import {getFailureReasonValues} from '../utils/helpers'
import {comma, createEnablementStatusProviders, ValuesFilterProvider} from '../utils/enablement-filter-helpers'

import styles from './SearchFilter.module.css'

interface SearchFilterProps {
  filterQuery: string
  onSubmit: (request: FilterQuery) => void
  onChange: (value: string) => void
  configurationNames: string[]
  definitions: PropertyDefinition[]
}

const CONFIG_NAME = {
  displayName: 'Configuration',
  key: 'configuration',
  description: '',
  priority: 2,
  icon: TasklistIcon,
}

const CONFIG_STATUS = {
  displayName: 'Configuration status',
  key: 'config-status',
  description: '',
  priority: 2,
  icon: TasklistIcon,
}

const CONFIG_STATUS_VALUES = [
  {value: 'attached', displayName: 'Attached', priority: 1},
  {value: 'removed', displayName: 'Removed', priority: 1},
  {value: 'failed', displayName: 'Failed', priority: 1},
  {value: 'enforced', displayName: 'Enforced', priority: 1},
  {value: 'removed_by_enterprise', displayName: 'Removed by enterprise', priority: 1},
]

const FAILURE_REASON = {
  displayName: 'Failure reason',
  key: 'failure-reason',
  description: '',
  priority: 2,
  icon: TasklistIcon,
}

const CONFIG_TEAM: FilterKey = {
  displayName: 'Team',
  key: 'team',
  description: '',
  priority: 2,
  icon: PeopleIcon,
}

const SearchFilter: React.FC<SearchFilterProps> = ({
  filterQuery,
  onSubmit,
  onChange,
  configurationNames,
  definitions,
}) => {
  const {capabilities, organization, securityProducts} = useAppContext()

  const getConfigurationNameOptions = (): FilterSuggestion[] => {
    const options: FilterSuggestion[] = []

    for (const element of configurationNames) {
      options.push({value: element, displayName: element, priority: 1})
    }

    options.push({value: 'None', displayName: 'None', priority: 2})

    return options
  }

  const getProviders = () => {
    const staticProviders = getAllStaticProviders()

    const filter = [
      ...staticProviders,
      getCustomPropertiesProvider(definitions),
      new LanguageFilterProvider(),
      new ValuesFilterProvider(CONFIG_NAME, getConfigurationNameOptions(), comma),
      new ValuesFilterProvider(CONFIG_STATUS, CONFIG_STATUS_VALUES, comma),
      new ValuesFilterProvider(FAILURE_REASON, getFailureReasonValues(), comma),
      ...createEnablementStatusProviders(capabilities, securityProducts),
    ]

    if (capabilities.hasTeams) filter.push(new TeamFilterProvider(organization, CONFIG_TEAM))

    return filter
  }

  return (
    <Filter
      providers={getProviders()}
      filterValue={filterQuery}
      onChange={onChange}
      onSubmit={onSubmit}
      id="repos-list-filter"
      label="Search repositories"
      placeholder="Search repositories"
      className={styles.Filter_0}
    />
  )
}

export default SearchFilter
