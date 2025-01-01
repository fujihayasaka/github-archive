import {Checkbox, FormControl, Heading} from '@primer/react'
import {useContext} from 'react'

import type {EditBudget} from '../../types/budgets'
import {PageContext} from '../../App'
import styles from './BudgetUserAlertSelector.module.css'

type BudgetUserAlertSelectorProps = {
  alertEnabled: EditBudget['alertEnabled']
  setAlertEnabled: (alertEnabled: EditBudget['alertEnabled']) => void
  setAlertRecipientUserIds: (alertRecipientUsers: string[]) => void
  defaultRecipient: string[]
}

export function BudgetUserAlertSelector({
  alertEnabled,
  setAlertEnabled,
  setAlertRecipientUserIds,
  defaultRecipient,
}: BudgetUserAlertSelectorProps) {
  const {isStafftoolsRoute} = useContext(PageContext)

  const toggleReceiveAlerts = () => {
    if (alertEnabled) {
      setAlertRecipientUserIds([])
    } else {
      setAlertRecipientUserIds(defaultRecipient)
    }
    setAlertEnabled(!alertEnabled)
  }

  return (
    <>
      <div className={styles.alertText}>
        <Heading as="h2" className={styles.Heading}>
          Alerts
        </Heading>
        <span>
          Get emails and GitHub notifications when your spending has reached 75%, 90%, and 100% of the budget threshold.
        </span>
      </div>
      <div className="Box">
        <div className="Box-row">
          <FormControl disabled={isStafftoolsRoute}>
            <Checkbox checked={alertEnabled} onChange={toggleReceiveAlerts} name="alert-checkbox" />
            <FormControl.Label>Receive budget threshold alerts</FormControl.Label>
          </FormControl>
        </div>
      </div>
    </>
  )
}
