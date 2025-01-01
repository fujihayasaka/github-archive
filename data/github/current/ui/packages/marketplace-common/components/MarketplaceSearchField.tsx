import {useFilterContext} from '../contexts/FilterContext'
import {useCategory} from '../contexts/CategoryContext'
import {useCallback, useMemo, useState} from 'react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {Filter, type FilterQuery} from '@github-ui/filter'
import styles from './marketplace-search-field.module.css'
import {filterStringFromQuery, queryFromFilterString} from '../utilities/filters'
import {ListingTypeFilterProvider} from '../utilities/filter-providers'
import {
  ModelsCategoryFilterProvider,
  ModelsPublisherFilterProvider,
  ModelsInputModalityFilterProvider,
  ModelsLanguageFilterProvider,
  ModelsLicenseFilterProvider,
  ModelsOutputModalityFilterProvider,
  ModelsTaskFilterProvider,
} from '../utilities/model-filter-providers'
import {useSearchType} from '../contexts/SearchTypeContext'
import {useCopilotApp} from '../contexts/CopilotAppContext'
import useAppsFilterProviders from '../hooks/use-apps-filter-providers'
import useActionsFilterProviders from '../hooks/use-actions-filter-providers'

const generalProviders = [ListingTypeFilterProvider]
const modelsProviders = [
  ModelsCategoryFilterProvider,
  ModelsPublisherFilterProvider,
  ModelsInputModalityFilterProvider,
  ModelsLanguageFilterProvider,
  ModelsLicenseFilterProvider,
  ModelsOutputModalityFilterProvider,
  ModelsTaskFilterProvider,
]

export default function MarketplaceSearchField() {
  const {query, onQueryChange: onQueryChangeV2} = useFilterContext()
  const {copilotApp, setCopilotApp} = useCopilotApp()
  const {type, setType} = useSearchType()
  const {category, setCategory} = useCategory()
  const initialFilter = useMemo(
    () => filterStringFromQuery(type, copilotApp, query, category),
    [query, type, copilotApp, category],
  )
  const includeModelsProviders = useFeatureFlag('github_models_search_filters')
  const [privateQuery, setPrivateQuery] = useState<string>(initialFilter)

  const appsProviders = useAppsFilterProviders()
  const actionsProviders = useActionsFilterProviders()

  const providers = useMemo(() => {
    let result = [...generalProviders]

    switch (type) {
      case 'actions':
        result = result.concat(actionsProviders)
        break
      case 'apps':
        result = result.concat(appsProviders)
        break
      case 'models':
        if (includeModelsProviders) result = result.concat(modelsProviders)
        break
      default:
        break
    }
    return result
  }, [includeModelsProviders, type, appsProviders, actionsProviders])

  const setQuery = useCallback(
    (filterStr: string) => {
      const {
        type: newType,
        copilotApp: newCopilotApp,
        query: newQuery,
        category: newCategory,
      } = queryFromFilterString(filterStr)
      setType(newType)
      setCopilotApp(newCopilotApp)
      setCategory(newCategory)
      onQueryChangeV2(newQuery || '', newType)
    },
    [onQueryChangeV2, setType, setCopilotApp, setCategory],
  )

  const handleQueryChange = useCallback(
    (value: string) => {
      setPrivateQuery(value)
    },
    [setPrivateQuery],
  )

  const handleSubmit = useCallback(
    (filterQuery: FilterQuery) => {
      setQuery(filterQuery.raw)
    },
    [setQuery],
  )

  return (
    <Filter
      id="marketplace-search-filter"
      data-testid="marketplace-search-filter"
      providers={providers}
      label="Search Marketplace"
      variant="input"
      filterValue={privateQuery}
      placeholder="Search for Copilot extensions, apps, actions, and models"
      className={`${styles['search-input']}`}
      settings={{
        disableAdvancedTextFilter: true,
        groupAndKeywordSupport: false,
      }}
      onChange={handleQueryChange}
      onSubmit={handleSubmit}
    />
  )
}
