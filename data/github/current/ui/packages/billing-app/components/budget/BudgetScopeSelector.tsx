import {Box, Heading, RadioGroup, FormControl, Radio, Spinner, Text} from '@primer/react'
import {useQueryLoader} from 'react-relay'
import {Suspense, useEffect, useContext} from 'react'
import {PageContext} from '../../App'

import {
  BUDGET_SCOPE_CUSTOMER,
  BUDGET_SCOPE_COST_CENTER,
  BUDGET_SCOPE_ORGANIZATION,
  BUDGET_SCOPE_REPOSITORY,
  HighWatermarkProducts,
} from '../../constants'
import {Spacing} from '../../utils'

import {CostCenterPicker} from '../pickers/CostCenterPicker'
import {OrganizationPicker, OrganizationPickerRecentQuery} from '../pickers/OrganizationPicker'
import {RepositoryPicker, RepositoryPickerRecentQuery} from '../pickers/RepositoryPicker'
import {OrgRepositoryPicker, OrgRepositoryPickerRecentQuery} from '../pickers/OrgRepositoryPicker'

import type {OrganizationPickerRecentQuery as OrganizationPickerQueryType} from '../pickers/__generated__/OrganizationPickerRecentQuery.graphql'
import type {RepositoryPickerRecentQuery as RepositoryPickerQueryType} from '../pickers/__generated__/RepositoryPickerRecentQuery.graphql'
import type {OrgRepositoryPickerRecentQuery as OrgRepositoryPickerQueryType} from '../pickers/__generated__/OrgRepositoryPickerRecentQuery.graphql'

import type {BudgetPicker} from '../../types/budgets'

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
  const isOrganizationRoute = useContext(PageContext).isOrganizationRoute
  const initialOrganizationScopeId = budgetScopeIds && budgetScope === BUDGET_SCOPE_ORGANIZATION ? budgetScopeIds : []
  const initialRepositoryScopeId = budgetScopeIds && budgetScope === BUDGET_SCOPE_REPOSITORY ? budgetScopeIds : []

  const [organizationsRef, loadOrganizations, disposeOrganizationsRef] =
    useQueryLoader<OrganizationPickerQueryType>(OrganizationPickerRecentQuery)

  const [repositoriesRef, loadRepositories, disposeRepositoriesRef] =
    useQueryLoader<RepositoryPickerQueryType>(RepositoryPickerRecentQuery)

  const [orgRepositoriesRef, loadOrgRepositories, disposeOrgRepositoriesRef] =
    useQueryLoader<OrgRepositoryPickerQueryType>(OrgRepositoryPickerRecentQuery)

  const isProductHighWaterMark = () => {
    return Object.values(HighWatermarkProducts).includes(budgetProduct as HighWatermarkProducts)
  }

  const orgViewOfHighWatermark = isProductHighWaterMark() && isOrganizationRoute

  useEffect(() => {
    if (!isOrganizationRoute) {
      loadOrganizations({slug}, {fetchPolicy: 'store-or-network'})
    }
    if (!disablePicker?.includes('repo')) {
      if (isOrganizationRoute) {
        loadOrgRepositories({slug}, {fetchPolicy: 'store-or-network'})
      } else {
        loadRepositories({slug}, {fetchPolicy: 'store-or-network'})
      }
    }
    if (orgViewOfHighWatermark) {
      setBudgetScope(BUDGET_SCOPE_CUSTOMER)
    }
    return () => {
      disposeOrganizationsRef()
      disposeRepositoriesRef()
      disposeOrgRepositoriesRef()
    }
  }, [
    slug,
    budgetScopeIds,
    budgetScope,
    loadOrganizations,
    loadRepositories,
    disposeOrganizationsRef,
    disposeRepositoriesRef,
    disablePicker,
    isOrganizationRoute,
    loadOrgRepositories,
    disposeOrgRepositoriesRef,
    orgViewOfHighWatermark,
    setBudgetScope,
  ])

  const handleBudgetScopeChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setBudgetScope(event.target.value)
    const scopeId = event.target.value === BUDGET_SCOPE_CUSTOMER ? ['1'] : []
    setBudgetScopeId(scopeId)
  }

  const setAllSelectedCostCenters = (selectedIds: string[]) => {
    if (selectedIds[0]) {
      setBudgetScopeId([selectedIds[0]])
    }
  }

  return (
    <Box sx={{paddingBottom: 2}}>
      <Heading as="h3" id="budget-scope-choices" sx={{fontSize: 2}} className="Box-title">
        Budget scope
      </Heading>
      <Text sx={{mb: 2}}>Select the scope of spending for this budget.</Text>
      <RadioGroup aria-labelledby="budget-scope-choices" name="budget-scope-choices" sx={{mb: Spacing.CardMargin}}>
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
                <FormControl.Label>Enterprise</FormControl.Label>
                <FormControl.Caption sx={{fontSize: 1}}>
                  Spending for all organizations and repositories in your enterprise.
                </FormControl.Caption>
              </FormControl>
            </div>
          )}
          {(!isProductHighWaterMark() || orgViewOfHighWatermark) && (
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
                    <FormControl.Label>Organization</FormControl.Label>
                    {isOrganizationRoute ? (
                      <FormControl.Caption sx={{fontSize: 1}}>
                        Spending for all repositories in your organization.
                      </FormControl.Caption>
                    ) : (
                      <FormControl.Caption sx={{fontSize: 1}}>Spending for a single organization.</FormControl.Caption>
                    )}
                  </FormControl>
                  {!isOrganizationRoute && budgetScope === BUDGET_SCOPE_ORGANIZATION && (
                    <Suspense fallback={<Spinner size="small" />}>
                      {organizationsRef && (
                        <OrganizationPicker
                          preloadedOrganizationsRef={organizationsRef}
                          slug={slug}
                          setSelectedItems={setBudgetScopeId}
                          initialSelectedItemIds={initialOrganizationScopeId}
                          selectionVariant="single"
                        />
                      )}
                    </Suspense>
                  )}
                </div>
              )}
              {!disablePicker?.includes('repo') && !orgViewOfHighWatermark && (
                <div className="Box-row">
                  <FormControl sx={{mb: budgetScope === BUDGET_SCOPE_REPOSITORY ? Spacing.StandardPadding : 0}}>
                    <Radio
                      checked={budgetScope === BUDGET_SCOPE_REPOSITORY}
                      value={BUDGET_SCOPE_REPOSITORY}
                      onChange={e => {
                        handleBudgetScopeChange(e)
                      }}
                    />
                    <FormControl.Label>Repository</FormControl.Label>
                    <FormControl.Caption sx={{fontSize: 1}}>Spending for a single repository.</FormControl.Caption>
                  </FormControl>
                  {budgetScope === BUDGET_SCOPE_REPOSITORY && (
                    <Suspense fallback={<Spinner size="small" />}>
                      {isOrganizationRoute && orgRepositoriesRef ? (
                        <OrgRepositoryPicker
                          preloadedRepositoriesRef={orgRepositoriesRef}
                          slug={slug}
                          setSelectedItems={setBudgetScopeId}
                          initialSelectedItemIds={initialRepositoryScopeId}
                          selectionVariant="single"
                        />
                      ) : (
                        repositoriesRef && (
                          <RepositoryPicker
                            preloadedRepositoriesRef={repositoriesRef}
                            slug={slug}
                            setSelectedItems={setBudgetScopeId}
                            initialSelectedItemIds={initialRepositoryScopeId}
                            selectionVariant="single"
                          />
                        )
                      )}
                    </Suspense>
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
                <FormControl.Label>Cost center</FormControl.Label>
                <FormControl.Caption sx={{fontSize: 1}}>Spending for a single cost center.</FormControl.Caption>
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
    </Box>
  )
}
