import {Box, Heading, Text, TextInput, Flash, FormControl, Checkbox} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {InfoIcon} from '@primer/octicons-react'
import {useState, useContext} from 'react'

import {PageContext} from '../../App'
import {COPILOT_LICENSE_COST, GHEC_LICENSE_COST, GHAS_LICENSE_COST, HighWatermarkProducts} from '../../constants'
import {BudgetLimitTypes} from '../../enums/budgets'

interface Props {
  budgetAmount: number | string
  budgetLimitType: BudgetLimitTypes
  setBudgetAmount: (budgetAmount: number | string) => void
  setBudgetLimitType: (budgetLimitType: BudgetLimitTypes) => void
  budgetProduct: string
  action: 'create' | 'edit'
}

export function BudgetAmount({
  budgetAmount,
  budgetLimitType,
  setBudgetAmount,
  setBudgetLimitType,
  budgetProduct,
  action,
}: Props) {
  const [validationMessage, setValidationMessage] = useState('')
  const isStafftoolsRoute = useContext(PageContext).isStafftoolsRoute

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value
    setValidationMessage('')
    if (e.type !== 'blur') {
      if (value === '' || !isNaN(Number(value))) {
        setBudgetAmount(value === '' ? value : Number(value))
      }
    } else if (value === '') {
      setBudgetAmount(0)
    }
  }

  const isProductHighWaterMark = () => {
    return Object.values(HighWatermarkProducts).includes(budgetProduct as HighWatermarkProducts)
  }

  const amountOfLicenses = () => {
    if (budgetProduct === HighWatermarkProducts.copilot) {
      return (
        <span>
          <b>~ {Math.floor((budgetAmount as number) / COPILOT_LICENSE_COST)} licenses</b>{' '}
          <Text sx={{color: 'fg.muted'}}>at ${COPILOT_LICENSE_COST}/license per month</Text>
        </span>
      )
    } else if (budgetProduct === HighWatermarkProducts.ghas) {
      return (
        <span>
          <b>~ {Math.floor((budgetAmount as number) / GHAS_LICENSE_COST)} licenses</b>{' '}
          <Text sx={{color: 'fg.muted'}}>at ${GHAS_LICENSE_COST}/license per month</Text>
        </span>
      )
    } else if (budgetProduct === HighWatermarkProducts.ghec) {
      return (
        <span>
          <b>~ {Math.floor((budgetAmount as number) / GHEC_LICENSE_COST)} licenses</b>{' '}
          <Text sx={{color: 'fg.muted'}}>at ${GHEC_LICENSE_COST}/license per month</Text>
        </span>
      )
    }
  }

  const toggleBudgetLimitType = () => {
    if (budgetLimitType === BudgetLimitTypes.AlertingOnly) {
      setBudgetLimitType(BudgetLimitTypes.PreventFurtherUsage)
    } else {
      setBudgetLimitType(BudgetLimitTypes.AlertingOnly)
    }
  }

  return (
    <>
      <Box sx={{paddingTop: 3, paddingBottom: 2}}>
        <Heading as="h3" sx={{fontSize: 2}} className="Box-title">
          Budget
        </Heading>
        <span>Set a budget amount to track your spending on a monthly basis.</span>
        {isProductHighWaterMark() && (
          <Flash sx={{display: 'flex', mt: 3, mb: 2}}>
            <Octicon icon={InfoIcon} size={20} sx={{mr: 2, pt: 1, color: 'accent.fg'}} />
            <span>
              Budgets for license-based products do not limit the usage, and continue to track any spending beyond the
              budget amount set by you.
            </span>
          </Flash>
        )}
      </Box>
      <div className="Box">
        <div className="Box-row">
          <Heading sx={{fontSize: 1}} as="h2">
            Budget amount
          </Heading>
          <div>
            <Box sx={{display: 'flex', fontSize: 1}}>
              <FormControl>
                <FormControl.Label visuallyHidden>BudgetAmountInput</FormControl.Label>
                <TextInput
                  inputMode="numeric"
                  pattern="^[0-9]+$" // only allow numbers
                  maxLength={10}
                  leadingVisual="$"
                  sx={{marginTop: 1, marginBottom: 3, maxWidth: '45em'}}
                  data-testid="budget-amount-input"
                  placeholder="0"
                  value={budgetAmount}
                  onChange={handleChange}
                  onBlur={handleChange}
                  name="budget-amount"
                />
                {validationMessage && (
                  <FormControl.Validation variant="error">{validationMessage}</FormControl.Validation>
                )}
              </FormControl>
              {isProductHighWaterMark() && <Text sx={{mt: 2, ml: 2}}>{amountOfLicenses()}</Text>}
            </Box>
            {!isProductHighWaterMark() && (
              <>
                <FormControl disabled={isStafftoolsRoute}>
                  <Checkbox
                    onChange={() => toggleBudgetLimitType()}
                    checked={budgetLimitType === BudgetLimitTypes.PreventFurtherUsage}
                    name="alert-checkbox"
                    data-testid="alert-checkbox"
                  />
                  <FormControl.Label>Stop usage when budget limit is reached</FormControl.Label>
                </FormControl>
                <Text sx={{color: 'fg.muted'}}>This will limit your spending to the budget amount set by you.</Text>
              </>
            )}
          </div>
          {action === 'create' && (
            <Box sx={{display: 'flex', mt: 2}}>
              <Octicon icon={InfoIcon} size={20} sx={{mr: 2, pt: 1, color: 'accent.fg'}} />
              <span>
                Usage that has been generated prior to budget creation might not be included in your budgets for the
                current billing cycle.
              </span>
            </Box>
          )}
        </div>
      </div>
    </>
  )
}
