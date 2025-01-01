import {Box, Heading, Text, TextInput, FormControl, Checkbox} from '@primer/react'
import {useState, useContext} from 'react'

import {PageContext} from '../../App'
import {
  GHEC_LICENSE_COST,
  GHAS_LICENSE_COST,
  HighWatermarkProducts,
  COPILOT_LICENSE_COST,
  HighWatermarkSkus,
} from '../../constants'
import {BudgetLimitTypes} from '../../enums/budgets'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {Banner} from '@primer/react/experimental'
import styles from './BudgetAmount.module.css'

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

  const isHighWatermark = () => {
    return (
      Object.values(HighWatermarkProducts).includes(budgetProduct as HighWatermarkProducts) ||
      Object.values(HighWatermarkSkus).includes(budgetProduct as HighWatermarkSkus)
    )
  }

  const isCopilotProduct = () => {
    return budgetProduct === HighWatermarkProducts.copilot
  }

  const amountOfLicenses = () => {
    if (budgetProduct === HighWatermarkProducts.copilot && !copilotPremiumSKUEnabled) {
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

  const stopBudgetText = isHighWatermark()
    ? 'Not available for license-based products'
    : "Spending won't exceed your set budget"

  const copilotPremiumSKUEnabled = isFeatureEnabled('billingplatform_copilot_premium_sku')

  return (
    <>
      <div>
        <Heading as="h2" className={styles.Heading}>
          Budget
        </Heading>
        <div className={styles.SubTitle}>
          <span>Set a budget amount to track your spending on a monthly basis.</span>
        </div>

        {action === 'create' && (
          <Banner data-testid="budget-usage-banner" title="budget-usage-banner" hideTitle className={styles.Banner}>
            <span>Usage before budget creation isn&apos;t counted in the current billing cycle.</span>
          </Banner>
        )}
        <Box className="Box" sx={{paddingTop: 2}}>
          <div className="Box-row">
            <Heading as="h4" className={styles.BudgetAmountHeading}>
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
                    sx={{marginTop: 1, marginBottom: 0, maxWidth: '45em'}}
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
                  {isCopilotProduct() && copilotPremiumSKUEnabled && (
                    <FormControl.Caption>
                      Budget amount will encompass both license costs and premium requests costs
                    </FormControl.Caption>
                  )}
                </FormControl>
                {isHighWatermark() && <Text sx={{mt: 2, ml: 2}}>{amountOfLicenses()}</Text>}
              </Box>
              <>
                <FormControl sx={{marginTop: 3}} disabled={isStafftoolsRoute || isHighWatermark()}>
                  <Checkbox
                    onChange={() => toggleBudgetLimitType()}
                    checked={budgetLimitType === BudgetLimitTypes.PreventFurtherUsage}
                    name="alert-checkbox"
                    data-testid="alert-checkbox"
                  />
                  <FormControl.Label>Stop usage when budget limit is reached</FormControl.Label>
                </FormControl>
                <Text sx={{color: 'fg.muted', paddingTop: 2, paddingBottom: 2, fontSize: '12px', ml: '25px'}}>
                  {stopBudgetText}
                </Text>
              </>
            </div>
          </div>
        </Box>
      </div>
    </>
  )
}
