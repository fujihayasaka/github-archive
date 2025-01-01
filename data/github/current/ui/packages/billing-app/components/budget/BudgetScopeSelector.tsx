import {RadioGroup, FormControl, Radio, Spinner, Heading} from '@primer/react'
import {useQueryLoader} from 'react-relay'
import {Suspense, useEffect, useContext} from 'react'
import {PageContext} from '../../App'

import {
  BUDGET_SCOPE_CUSTOMER,
  BUDGET_SCOPE_COST_CENTER,
  BUDGET_SCOPE_ORGANIZATION,
  BUDGET_SCOPE_REPOSITORY,
  HighWatermarkProducts,
  HighWatermarkSkus,
  CopilotPremiumRequestSku,
} from '../../constants'
import {Spacing} from '../../utils'

import {CostCenterPicker} from '../pickers/CostCenterPicker'
import {OrgRepositoryPicker, OrgRepositoryPickerRecentQuery} from '../pickers/OrgRepositoryPicker'
import {UserRepositoryPicker, UserRepositoryPickerRecentQuery} from '../pickers/UserRepositoryPicker'

import type {OrgRepositoryPickerRecentQuery as OrgRepositoryPickerQueryType} from '../pickers/__generated__/OrgRepositoryPickerRecentQuery.graphql'
import type {UserRepositoryPickerRecentQuery as UserRepositoryPickerQueryType} from '../pickers/__generated__/UserRepositoryPickerRecentQuery.graphql'

import type {BudgetPicker} from '../../types/budgets'
import {OrganizationPickerParentGraphqlQuery, PaginatedOrganizationPicker} from '../pickers/PaginatedOrganizationPicker'
import type {PaginatedOrganizationPickerGraphqlQuery} from '../pickers/__generated__/PaginatedOrganizationPickerGraphqlQuery.graphql'

import styles from './BudgetScopeSelector.module.css'
import type {PaginatedRepositoryPickerGraphqlQuery} from '../pickers/__generated__/PaginatedRepositoryPickerGraphqlQuery.graphql'
import {
  PaginatedRepositoryPicker,
  PaginatedRepositoryPickerParentGraphqlQuery,
} from '../pickers/PaginatedRepositoryPicker'

interface Props {
  budgetScope: string
  setBudgetScope: (budgetScope: string) => void
  setBudgetScopeId: (budgetScopeIds: string[]) => void
  budgetScopeIds: string[]
  slug: string
  disablePicker?: BudgetPicker[]
  budgetProduct: string
}

export function BudgetScopeSelector({
  budgetScope,
  setBudgetScope,
  setBudgetScopeId,
  budgetScopeIds,
  slug,
  disablePicker,
  budgetProduct,
}: Props) {
  const {isOrganizationRoute, isEnterpriseRoute, isUserRoute} = useContext(PageContext)
  const initialOrganizationScopeId = budgetScopeIds && budgetScope === BUDGET_SCOPE_ORGANIZATION ? budgetScopeIds : []
  const initialRepositoryScopeId = budgetScopeIds && budgetScope === BUDGET_SCOPE_REPOSITORY ? budgetScopeIds : []

  const [paginatedOrganizationsRef, loadPaginatedOrganizations, disposePaginatedOrganizationsRef] =
    useQueryLoader<PaginatedOrganizationPickerGraphqlQuery>(OrganizationPickerParentGraphqlQuery)

  const [paginatedRepositoriesRef, loadPaginatedRepositories, disposePaginatedRepositoriesRef] =
    useQueryLoader<PaginatedRepositoryPickerGraphqlQuery>(PaginatedRepositoryPickerParentGraphqlQuery)

  const [orgRepositoriesRef, loadOrgRepositories, disposeOrgRepositoriesRef] =
    useQueryLoader<OrgRepositoryPickerQueryType>(OrgRepositoryPickerRecentQuery)

  const [userRepositoriesRef, loadUserRepositories, disposeUserRepositoriesRef] =
    useQueryLoader<UserRepositoryPickerQueryType>(UserRepositoryPickerRecentQuery)

  const isProductHighWaterMark = () => {
    return (
      Object.values(HighWatermarkProducts).includes(budgetProduct as HighWatermarkProducts) ||
      Object.values(HighWatermarkSkus).includes(budgetProduct as HighWatermarkSkus)
    )
  }

  const orgViewOfHighWatermark = isProductHighWaterMark() && isOrganizationRoute

  useEffect(() => {
    if (isEnterpriseRoute) {
      loadPaginatedOrganizations({slug}, {fetchPolicy: 'store-or-network'})
    }
    if (!disablePicker?.includes('repo')) {
      if (isOrganizationRoute) {
        loadOrgRepositories({slug}, {fetchPolicy: 'store-or-network'})
      } else if (isUserRoute) {
        loadUserRepositories({}, {fetchPolicy: 'store-or-network'})
      } else {
        loadPaginatedRepositories({slug}, {fetchPolicy: 'store-or-network'})
      }
    }
    if (orgViewOfHighWatermark) {
      setBudgetScope(BUDGET_SCOPE_CUSTOMER)
    }

    return () => {
      disposePaginatedOrganizationsRef()
      disposeOrgRepositoriesRef()
      disposeUserRepositoriesRef()
      disposePaginatedRepositoriesRef()
    }
  }, [
    slug,
    budgetScopeIds,
    budgetScope,
    loadPaginatedOrganizations,
    disposePaginatedOrganizationsRef,
    disablePicker,
    isOrganizationRoute,
    loadOrgRepositories,
    disposeOrgRepositoriesRef,
    orgViewOfHighWatermark,
    setBudgetScope,
    loadUserRepositories,
    disposeUserRepositoriesRef,
    isEnterpriseRoute,
    isUserRoute,
    loadPaginatedRepositories,
    disposePaginatedRepositoriesRef,
  ])

  const handleBudgetScopeChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setBudgetScope(event.target.value)
    const scopeId = event.target.value === BUDGET_SCOPE_CUSTOMER ? ['1'] : []
    setBudgetScopeId(scopeId)
  }

  const isCopilotProduct = (product: string) => {
    return (
      product === HighWatermarkProducts.copilot ||
      product === HighWatermarkSkus.copilot_standalone ||
      product === HighWatermarkSkus.copilot_for_business ||
      product === HighWatermarkSkus.copilot_enterprise ||
      product === CopilotPremiumRequestSku
    )
  }

  const setAllSelectedCostCenters = (selectedIds: string[]) => {
    if (selectedIds[0]) {
      setBudgetScopeId([selectedIds[0]])
    }
  }

  const visibleBudgetScopes = [
    !disablePicker?.includes('enterprise') && BUDGET_SCOPE_CUSTOMER,
    !disablePicker?.includes('org') && BUDGET_SCOPE_ORGANIZATION,
    isUserRoute && BUDGET_SCOPE_CUSTOMER,
    !disablePicker?.includes('repo') &&
      !orgViewOfHighWatermark &&
      !(isUserRoute && isCopilotProduct(budgetProduct)) &&
      BUDGET_SCOPE_REPOSITORY,
    !disablePicker?.includes('cost_center') && BUDGET_SCOPE_COST_CENTER,
  ].filter(Boolean)

  const isSingleScope = visibleBudgetScopes.length === 1

  const getScopeLabel = (scope: string | undefined): string => {
    switch (scope) {
      case BUDGET_SCOPE_CUSTOMER:
        // Handle CUSTOMER scope differently based on the route
        if (isUserRoute) {
          return 'Account'
        } else if (isOrganizationRoute) {
          return 'Organization'
        } else {
          return 'Enterprise'
        }
      case BUDGET_SCOPE_ORGANIZATION:
        return 'Organization'
      case BUDGET_SCOPE_REPOSITORY:
        return 'Repository'
      case BUDGET_SCOPE_COST_CENTER:
        return 'Cost center'
      default:
        return 'Account'
    }
  }

  const getScopeDescription = (scope: string | undefined): string => {
    switch (scope) {
      case BUDGET_SCOPE_CUSTOMER:
        // Handle CUSTOMER scope differently based on the route
        if (isUserRoute) {
          if (isCopilotProduct(budgetProduct)) {
            return 'All spending for your account'
          } else {
            return 'Spending for all repositories owned by your account.'
          }
        } else if (isOrganizationRoute) {
          return 'Spending for all repositories in your organization.'
        } else {
          return 'Spending for all organizations and repositories in your enterprise.'
        }
      case BUDGET_SCOPE_ORGANIZATION:
        return 'Spending for all repositories in your organization.'
      case BUDGET_SCOPE_REPOSITORY:
        return 'Spending for a single repository.'
      case BUDGET_SCOPE_COST_CENTER:
        return 'Spending for a single cost center.'
      default:
        return 'Spending for all repositories owned by your account.'
    }
  }

  if (isSingleScope) {
    const singleScope = visibleBudgetScopes[0] as string
    setBudgetScope(singleScope)

    return (
      <div>
        <Heading as="h2" id="budget-scope-choices" className={styles.Heading}>
          Budget scope
        </Heading>
        <div className={styles.BudgetSubTitleBox}>
          <span>Select the scope of spending for this budget.</span>
        </div>
        <div className="Box">
          <div className="Box-row">
            <FormControl>
              <FormControl.Label>{getScopeLabel(singleScope)}</FormControl.Label>
              <FormControl.Caption sx={{fontSize: 1}}>{getScopeDescription(singleScope)}</FormControl.Caption>
            </FormControl>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div>
      <Heading as="h2" id="budget-scope-choices" className={styles.Heading}>
        Budget scope
      </Heading>
      <div className={styles.BudgetSubTitleBox}>
        <span>Select the scope of spending for this budget.</span>
      </div>
      <RadioGroup aria-labelledby="budget-scope-choices" name="budget-scope-choices">
        <div className="Box">
          {!disablePicker?.includes('enterprise') && (
            <div className="Box-row">
              <FormControl>
                <Radio
                  checked={budgetScope === BUDGET_SCOPE_CUSTOMER}
                  value={BUDGET_SCOPE_CUSTOMER}
                  onChange={e => {
                    handleBudgetScopeChange(e)
                  }}
                />
                <FormControl.Label>{getScopeLabel(BUDGET_SCOPE_CUSTOMER)}</FormControl.Label>
                <FormControl.Caption sx={{fontSize: 1}}>
                  {getScopeDescription(BUDGET_SCOPE_CUSTOMER)}
                </FormControl.Caption>
              </FormControl>
            </div>
          )}
          {((isUserRoute && isProductHighWaterMark()) || !isProductHighWaterMark() || orgViewOfHighWatermark) && (
            <>
              {!disablePicker?.includes('org') && (
                <div className="Box-row">
                  <FormControl
                    sx={{mb: budgetScope === BUDGET_SCOPE_ORGANIZATION ? Spacing.StandardPadding : 0}}
                    disabled={orgViewOfHighWatermark}
                  >
                    <Radio
                      value={isOrganizationRoute ? BUDGET_SCOPE_CUSTOMER : BUDGET_SCOPE_ORGANIZATION}
                      checked={
                        orgViewOfHighWatermark ||
                        budgetScope === BUDGET_SCOPE_ORGANIZATION ||
                        (isOrganizationRoute && budgetScope === BUDGET_SCOPE_CUSTOMER)
                      }
                      onChange={e => {
                        handleBudgetScopeChange(e)
                      }}
                    />
                    <FormControl.Label>{getScopeLabel(BUDGET_SCOPE_ORGANIZATION)}</FormControl.Label>
                    <FormControl.Caption sx={{fontSize: 1}}>
                      {getScopeDescription(BUDGET_SCOPE_ORGANIZATION)}
                    </FormControl.Caption>
                  </FormControl>
                  {!isOrganizationRoute && budgetScope === BUDGET_SCOPE_ORGANIZATION && (
                    <Suspense fallback={<Spinner size="small" />}>
                      {paginatedOrganizationsRef && (
                        <PaginatedOrganizationPicker
                          preloadedOrganizationsRef={paginatedOrganizationsRef}
                          setSelectedItems={setBudgetScopeId}
                          initialSelectedItemIds={initialOrganizationScopeId}
                          selectionVariant="single"
                        />
                      )}
                    </Suspense>
                  )}
                </div>
              )}
              {isUserRoute && (
                <div className="Box-row">
                  <FormControl>
                    <Radio
                      checked={budgetScope === BUDGET_SCOPE_CUSTOMER}
                      value={BUDGET_SCOPE_CUSTOMER}
                      onChange={e => {
                        handleBudgetScopeChange(e)
                      }}
                    />
                    <FormControl.Label>{getScopeLabel(BUDGET_SCOPE_CUSTOMER)}</FormControl.Label>
                    <FormControl.Caption sx={{fontSize: 1}}>
                      {getScopeDescription(BUDGET_SCOPE_CUSTOMER)}
                    </FormControl.Caption>
                  </FormControl>
                </div>
              )}
              {!disablePicker?.includes('repo') &&
                !orgViewOfHighWatermark &&
                !(isUserRoute && isCopilotProduct(budgetProduct)) && (
                  <div className="Box-row">
                    <FormControl sx={{mb: budgetScope === BUDGET_SCOPE_REPOSITORY ? Spacing.StandardPadding : 0}}>
                      <Radio
                        checked={budgetScope === BUDGET_SCOPE_REPOSITORY}
                        value={BUDGET_SCOPE_REPOSITORY}
                        onChange={e => {
                          handleBudgetScopeChange(e)
                        }}
                      />
                      <FormControl.Label>{getScopeLabel(BUDGET_SCOPE_REPOSITORY)}</FormControl.Label>
                      <FormControl.Caption sx={{fontSize: 1}}>
                        {getScopeDescription(BUDGET_SCOPE_REPOSITORY)}
                      </FormControl.Caption>
                    </FormControl>
                    {budgetScope === BUDGET_SCOPE_REPOSITORY && (
                      <>
                        {isOrganizationRoute && orgRepositoriesRef && (
                          <Suspense fallback={<Spinner size="small" />}>
                            <OrgRepositoryPicker
                              preloadedRepositoriesRef={orgRepositoriesRef}
                              slug={slug}
                              setSelectedItems={setBudgetScopeId}
                              initialSelectedItemIds={initialRepositoryScopeId}
                              selectionVariant="single"
                            />
                          </Suspense>
                        )}
                        {isUserRoute && userRepositoriesRef && (
                          <Suspense fallback={<Spinner size="small" />}>
                            <UserRepositoryPicker
                              preloadedRepositoriesRef={userRepositoriesRef}
                              setSelectedItems={setBudgetScopeId}
                              initialSelectedItemIds={initialRepositoryScopeId}
                              selectionVariant="single"
                            />
                          </Suspense>
                        )}
                        {paginatedRepositoriesRef && isEnterpriseRoute && (
                          <Suspense fallback={<Spinner size="small" />}>
                            <PaginatedRepositoryPicker
                              preloadedRepositoriesRef={paginatedRepositoriesRef}
                              slug={slug}
                              setSelectedItems={setBudgetScopeId}
                              initialSelectedItemIds={initialRepositoryScopeId}
                              selectionVariant="single"
                            />
                          </Suspense>
                        )}
                      </>
                    )}
                  </div>
                )}
            </>
          )}
          {!disablePicker?.includes('cost_center') && (
            <div className="Box-row">
              <FormControl sx={{mb: budgetScope === BUDGET_SCOPE_COST_CENTER ? Spacing.StandardPadding : 0}}>
                <Radio
                  checked={budgetScope === BUDGET_SCOPE_COST_CENTER}
                  value={BUDGET_SCOPE_COST_CENTER}
                  onChange={e => {
                    handleBudgetScopeChange(e)
                  }}
                />
                <FormControl.Label>{getScopeLabel(BUDGET_SCOPE_COST_CENTER)}</FormControl.Label>
                <FormControl.Caption sx={{fontSize: 1}}>
                  {getScopeDescription(BUDGET_SCOPE_COST_CENTER)}
                </FormControl.Caption>
              </FormControl>
              {budgetScope === BUDGET_SCOPE_COST_CENTER && (
                <Suspense fallback={<Spinner size="small" />}>
                  <CostCenterPicker
                    initialSelectedItems={[]}
                    setAllSelectedCostCenters={setAllSelectedCostCenters}
                    selectionVariant="single"
                  />
                </Suspense>
              )}
            </div>
          )}
        </div>
      </RadioGroup>
    </div>
  )
}
