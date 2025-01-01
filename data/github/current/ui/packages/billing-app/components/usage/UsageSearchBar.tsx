import type {KeyboardEventHandler} from 'react'
import {useState, useCallback, useRef, useContext} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {QueryBuilder} from '@github-ui/query-builder/QueryBuilder'
import {useDebounce} from '@github-ui/use-debounce'
import type {QueryBuilderElement} from '@github-ui/query-builder-element'
import {EnterpriseOrgFilterProvider} from '@github-ui/query-builder/providers/billing/enterprise-org-filter-provider'
import {EnterpriseRepoFilterProvider} from '@github-ui/query-builder/providers/billing/enterprise-repo-filter-provider'
import {OrganizationRepoFilterProvider} from '@github-ui/query-builder/providers/billing/organization-repo-filter-provider'
import {BillingProductFilterProvider} from '@github-ui/query-builder/providers/billing/billing-product-filter-provider'
import {BillingSKUFilterProvider} from '@github-ui/query-builder/providers/billing/billing-sku-filter-provider'
import {BillingCostCenterFilterProvider} from '@github-ui/query-builder/providers/billing/billing-costcenter-filter-provider'
import {UserRepoFilterProvider} from '@github-ui/query-builder/providers/billing/user-repo-filter-provider'

import type {Customer} from '../../types/common'
import {PageContext} from '../../App'
import type {UsageGrouping} from '../../enums'
import {
  GROUP_BY_ORG_TYPE,
  GROUP_BY_COSTCENTER_TYPE,
  GROUP_BY_PRODUCT_TYPE,
  GROUP_BY_REPO_TYPE,
  GROUP_BY_SKU_TYPE,
  GROUP_BY_NONE_TYPE,
} from '../../constants'
import type {EnabledProduct} from '../../types/products'

interface Props {
  customer: Customer
  searchQuery: string
  setSearchQuery: (query: string) => void
  selectedGroup: UsageGrouping | undefined
  enabledProducts: EnabledProduct[]
}

const DEFAULT_ENABLED_PRODUCTS: EnabledProduct[] = []

const UsageSearchBar = ({
  customer,
  setSearchQuery,
  searchQuery,
  selectedGroup,
  enabledProducts = DEFAULT_ENABLED_PRODUCTS,
}: Props) => {
  const [inputQuery, setInputQuery] = useState<string>(searchQuery)
  const relayEnvironment = useRelayEnvironment()
  const ref = useRef(null)
  const {isEnterpriseRoute, isOrganizationRoute, isUserRoute} = useContext(PageContext)

  const shouldAddSearchFilter = useCallback(
    (filterValue: string): boolean => {
      // the available search filters based on the currently selected group
      const GROUP_SEARCH_FILTER_MAPPING: Record<UsageGrouping, string[]> = {
        [GROUP_BY_NONE_TYPE]: ['cost_center', 'org', 'product', 'repo', 'sku'],
        [GROUP_BY_ORG_TYPE]: ['cost_center'],
        [GROUP_BY_REPO_TYPE]: ['cost_center'],
        [GROUP_BY_PRODUCT_TYPE]: ['cost_center', 'org', 'repo'],
        [GROUP_BY_COSTCENTER_TYPE]: ['cost_center', 'org', 'repo'],
        [GROUP_BY_SKU_TYPE]: ['cost_center', 'org', 'product', 'repo'],
      } as const
      if (selectedGroup === undefined) return false
      return GROUP_SEARCH_FILTER_MAPPING[selectedGroup]?.includes(filterValue) ?? false
    },
    [selectedGroup],
  )

  const addEnterpriseSearchFilters = useCallback(
    (queryBuilder: QueryBuilderElement) => {
      const enterpriseFilters = [
        {
          Provider: EnterpriseOrgFilterProvider,
          config: {
            name: 'Organization',
            value: 'org',
            priority: 2,
            relayEnvironment,
          },
        },
        {
          Provider: EnterpriseRepoFilterProvider,
          config: {
            name: 'Repository',
            value: 'repo',
            priority: 3,
            relayEnvironment,
          },
        },
        {
          Provider: BillingCostCenterFilterProvider,
          config: {
            name: 'Cost Center',
            value: 'cost_center',
            priority: 1,
          },
        },
      ]

      for (const {Provider, config} of enterpriseFilters) {
        if (shouldAddSearchFilter(config.value)) {
          new Provider(queryBuilder, {
            ...config,
            slug: customer.displayId,
            relayEnvironment: config.relayEnvironment ?? relayEnvironment,
          })
        }
      }
    },
    [customer.displayId, relayEnvironment, shouldAddSearchFilter],
  )

  const addOrgSearchFilters = useCallback(
    (queryBuilder: QueryBuilderElement) => {
      if (shouldAddSearchFilter('repo')) {
        // Current organization repository data from GraphQL
        new OrganizationRepoFilterProvider(queryBuilder, {
          name: 'Repository',
          value: 'repo',
          slug: customer.displayId,
          priority: 3,
          relayEnvironment,
        })
      }
    },
    [customer.displayId, relayEnvironment, shouldAddSearchFilter],
  )

  const addCommonSearchFilters = useCallback(
    (queryBuilder: QueryBuilderElement) => {
      // Add repository filter based on whether it's an organization or individual user
      if (shouldAddSearchFilter('repo')) {
        if (isOrganizationRoute) {
          // Organization repository data from GraphQL
          new OrganizationRepoFilterProvider(queryBuilder, {
            name: 'Repository',
            value: 'repo',
            slug: customer.displayId,
            priority: 3,
            relayEnvironment,
          })
        } else {
          // Individual user repository data from GraphQL
          new UserRepoFilterProvider(queryBuilder, {
            name: 'Repository',
            value: 'repo',
            username: customer.displayId,
            priority: 3,
            relayEnvironment,
          })
        }
      }

      // Product/SKU data from billing-platform (non-GQL)
      const commonFilters = [
        {
          Provider: BillingProductFilterProvider,
          config: {
            name: 'Product',
            value: 'product',
            priority: 4,
            isOrgRoute: isOrganizationRoute,
            isUserRoute,
            enabledProducts: enabledProducts.map(product => product.name),
          },
        },
        {
          Provider: BillingSKUFilterProvider,
          config: {
            name: 'SKU',
            value: 'sku',
            priority: 5,
            isOrgRoute: isOrganizationRoute,
            isUserRoute,
            enabledProducts: enabledProducts.map(product => product.name),
          },
        },
      ]

      for (const {Provider, config} of commonFilters) {
        if (shouldAddSearchFilter(config.value)) {
          new Provider(queryBuilder, {
            ...config,
            slug: customer.displayId,
          })
        }
      }
    },
    [customer.displayId, isOrganizationRoute, isUserRoute, enabledProducts, shouldAddSearchFilter, relayEnvironment],
  )

  /**
   * Populates the search dropdown with the filters (org, repo, product, sku) and
   * their respective values.
   *
   * TODO: This needs additional logic considerations for Orgs and Individuals
   */
  const onRequestProvider = useCallback(
    (event: Event) => {
      event.stopPropagation()
      const queryBuilder = event.target as QueryBuilderElement

      if (isEnterpriseRoute) {
        addEnterpriseSearchFilters(queryBuilder)
      }

      if (isOrganizationRoute) {
        addOrgSearchFilters(queryBuilder)
      }

      addCommonSearchFilters(queryBuilder)
    },
    [addCommonSearchFilters, addEnterpriseSearchFilters, addOrgSearchFilters, isEnterpriseRoute, isOrganizationRoute],
  )

  // Create a debounced version of setSearchQuery that waits 400ms after the last call to execute
  const debouncedSetSearchQuery = useDebounce(setSearchQuery, 400)

  const onChangeHandler: React.ChangeEventHandler<HTMLInputElement> = useCallback(
    event => {
      const currentInputQuery = inputQuery
      const newInputQuery = event.currentTarget.value

      if (newInputQuery !== currentInputQuery) {
        // Usage was cleared, we should reset the query value
        if (newInputQuery === '') {
          setSearchQuery('')
          setInputQuery('')
          return
        }

        setInputQuery(newInputQuery)
        // Only submit the query if the user has finished typing/selecting a filter and the filter has at least some
        // value attached (e.g. "org:github").
        const searchCount = newInputQuery.split(':').length - 1
        if (newInputQuery && newInputQuery.includes(':') && !newInputQuery.trim().endsWith(':') && searchCount === 1) {
          debouncedSetSearchQuery(newInputQuery.trim())
        }
      }
    },
    [inputQuery, setSearchQuery, debouncedSetSearchQuery],
  )

  const handleEnterKeyPress: KeyboardEventHandler = useCallback(
    event => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic -- manual shortcut logic is idiomatic in React
      if (event.key !== 'Enter') return
      event.preventDefault()
      const searchCount = inputQuery.split(':').length - 1
      if (searchCount === 1) {
        setSearchQuery(inputQuery.trim())
      }
    },
    [inputQuery, setSearchQuery],
  )

  return (
    <QueryBuilder
      id="usage-query-builder"
      label="Search or filter usage (chart updates as you type)"
      onChange={onChangeHandler}
      onKeyPress={handleEnterKeyPress}
      inputValue={inputQuery}
      placeholder="Search or filter usage"
      onRequestProvider={onRequestProvider}
      data-testid="search-usage"
      inputRef={ref}
      key={selectedGroup}
    />
  )
}

export default UsageSearchBar
