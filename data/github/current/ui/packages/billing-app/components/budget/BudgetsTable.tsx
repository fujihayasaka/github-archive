import {useState, useEffect} from 'react'
import {Box, Text, Pagination, ActionMenu, ActionList} from '@primer/react'

import {BUDGET_SCOPE_ORGANIZATION, BUDGET_SCOPE_REPOSITORY} from '../../constants'

import {boxStyle, tableContainerStyle, tableHeaderStyle} from '../../utils/style'

import {BudgetPricingTargetType, type Budget} from '../../types/budgets'
import BudgetData from './BudgetData'
import type {Product} from '../../types/products'
import type {PricingDetails} from '../../types/pricings'

type Props = {
  budgets: Budget[]
  deleteBudget: (budgetUuid: string) => void
  isCustomerTable?: boolean
  customerTableLabel?: string
  enabledProducts: Product[]
  enabledSkus?: PricingDetails[]
  isEnterpriseRoute?: boolean
  hasBudgetWritePermissions?: boolean
  copilotIapSubscription: boolean
}

export default function BudgetsTable({
  budgets,
  deleteBudget,
  isCustomerTable = false,
  customerTableLabel = 'Enterprise',
  enabledProducts,
  enabledSkus,
  isEnterpriseRoute = true,
  hasBudgetWritePermissions = false,
  copilotIapSubscription,
}: Props) {
  const pageSize = 10
  const [pageNumber, setPageNumber] = useState(1)
  const [currentPage, setCurrentPage] = useState(1)
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [currData, setCurrData] = useState<Budget[]>([])
  const [pagedData, setPagedData] = useState<Budget[]>([])
  const scopeTypes = ['All', 'Organizations', 'Repositories']

  const onPageChange: Parameters<typeof Pagination>['0']['onPageChange'] = (e, page) => {
    e.preventDefault()
    setCurrentPage(page)
  }

  useEffect(() => {
    const updatePagedData = async () => {
      setPageNumber(Math.ceil(currData.length / (1.0 * pageSize)) || 1)
      setPagedData(currData.slice((currentPage - 1) * pageSize, currentPage * pageSize))
    }
    updatePagedData()
  }, [currData, currentPage])

  useEffect(() => {
    let resourceType = 'All'
    let currBudgets: Budget[]
    switch (selectedIndex) {
      case 1: {
        resourceType = BUDGET_SCOPE_ORGANIZATION
        break
      }
      case 2: {
        resourceType = BUDGET_SCOPE_REPOSITORY
        break
      }
    }
    if (resourceType !== 'All') {
      currBudgets = budgets.filter(budget => budget.targetType === resourceType)
    } else {
      currBudgets = budgets
    }
    currBudgets = currBudgets.filter(budget => {
      // TODO: remove this "pricingTargetType" check when we confirm it doesn't break Copilot Premium budgets
      if (budget.pricingTargetType !== BudgetPricingTargetType.ProductPricing) return true
      return enabledProducts.find(product => budget.pricingTargetId === product.name)
    })
    setCurrentPage(1)
    setCurrData(currBudgets)
  }, [selectedIndex, budgets, enabledProducts])

  return (
    <>
      <Box sx={{...boxStyle, p: 0}}>
        <Box as="table" sx={tableContainerStyle} data-hpc>
          <Box
            as="thead"
            sx={{
              ...tableHeaderStyle,
              alignItems: 'center',
              display: 'flex',
            }}
          >
            <Box as="tr" sx={{flex: 1}}>
              <Box as="td" sx={{float: 'left', mt: '6px', mb: '6px'}}>
                <Text sx={{fontWeight: 'bold'}}>
                  {isCustomerTable ? `${customerTableLabel} budgets` : `${currData.length} budgets`}
                </Text>
              </Box>
              <Box as="td" sx={{float: 'right'}}>
                {!isCustomerTable && isEnterpriseRoute && (
                  <ActionMenu>
                    <ActionMenu.Button variant="invisible" sx={{color: 'btn.text'}}>
                      <Text sx={{fontWeight: 'normal'}}>Scope: {scopeTypes[selectedIndex] ?? 'All'}</Text>
                    </ActionMenu.Button>
                    <ActionMenu.Overlay>
                      <ActionList>
                        <ActionList.Group selectionVariant="single">
                          <ActionList.GroupHeading>Filter scope</ActionList.GroupHeading>
                          {scopeTypes.map((scopeType, index) => (
                            <ActionList.Item
                              // eslint-disable-next-line @eslint-react/no-array-index-key
                              key={index}
                              selected={index === selectedIndex}
                              onSelect={() => setSelectedIndex(index)}
                            >
                              {scopeType}
                            </ActionList.Item>
                          ))}
                        </ActionList.Group>
                      </ActionList>
                    </ActionMenu.Overlay>
                  </ActionMenu>
                )}
              </Box>
            </Box>
          </Box>
          <tbody>
            {pagedData.map(budgetData => {
              return (
                <BudgetData
                  key={budgetData.uuid}
                  budgetData={budgetData}
                  hasBudgetWritePermissions={hasBudgetWritePermissions}
                  deleteBudget={deleteBudget}
                  enabledProducts={enabledProducts}
                  enabledSkus={enabledSkus}
                  copilotIapSubscription={copilotIapSubscription}
                />
              )
            })}
          </tbody>
        </Box>
      </Box>
      {currData.length > pageSize && (
        <Pagination pageCount={pageNumber} currentPage={currentPage} onPageChange={onPageChange} />
      )}
    </>
  )
}
