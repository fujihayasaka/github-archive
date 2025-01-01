import {Box, Checkbox, FormControl, Heading, Spinner} from '@primer/react'
import type {User} from '../pickers/UserPicker'
import {UserPickerUserFragment, UserPickerInitialUsersQuery} from '../pickers/UserPicker'
import {fetchQuery, readInlineData, useRelayEnvironment} from 'react-relay'
import {Suspense, useEffect, useState, useContext} from 'react'
import type {UserPickerInitialUsersQuery as UserPickerInitialUsersQueryType} from '../pickers/__generated__/UserPickerInitialUsersQuery.graphql'
import type {UserPickerUserFragment$key} from '../pickers/__generated__/UserPickerUserFragment.graphql'
import {OrgUserPicker} from '../pickers/OrgUserPicker'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'

import type {EditBudget} from '../../types/budgets'
import {PageContext} from '../../App'

interface Props {
  alertEnabled: EditBudget['alertEnabled']
  alertRecipientUserIds: string[]
  setAlertEnabled: (alertEnabled: EditBudget['alertEnabled']) => void
  setAlertRecipientUserIds: (alertRecipientUsers: string[]) => void
  orgName: string
}

export function BudgetOrgAlertSelector({
  alertEnabled,
  alertRecipientUserIds,
  setAlertEnabled,
  setAlertRecipientUserIds,
  orgName,
}: Props) {
  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()
  const [loading, setLoading] = useState<boolean>(false)
  const [initialRecipients, setInitialRecipients] = useState<User[]>([])
  const isStafftoolsRoute = useContext(PageContext).isStafftoolsRoute

  const toggleReceiveAlerts = () => {
    setAlertEnabled(!alertEnabled)
  }

  const handleRecipientsChange = (users: User[]) => {
    const selectedRecipients = users.filter(u => !!u.id).map(u => u.id)
    setAlertRecipientUserIds(selectedRecipients)
  }

  useEffect(() => {
    setLoading(true)
    fetchQuery<UserPickerInitialUsersQueryType>(environment, UserPickerInitialUsersQuery, {
      ids: alertRecipientUserIds,
    }).subscribe({
      next: data => {
        const nodes = (data.nodes || []).flatMap(node =>
          // eslint-disable-next-line no-restricted-syntax
          node ? [readInlineData<UserPickerUserFragment$key>(UserPickerUserFragment, node)] : [],
        )
        handleRecipientsChange(nodes)
        setInitialRecipients(nodes)
        setLoading(false)
      },
      error: () => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({type: 'error', message: 'Unable to get current user', role: 'alert'})
        setLoading(false)
      },
    })
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [environment])

  return (
    <>
      <Box sx={{paddingBottom: 2, paddingTop: 3}}>
        <Heading as="h3" sx={{fontSize: 2}} className="Box-title">
          Alerts
        </Heading>
        <span>
          Get emails and GitHub notifications when your spending has reached 75%, 90%, and 100% of the budget threshold.
        </span>
      </Box>
      <div className="Box">
        <div className="Box-row">
          <FormControl disabled={isStafftoolsRoute}>
            <Checkbox checked={alertEnabled} onChange={toggleReceiveAlerts} name="alert-checkbox" />
            <FormControl.Label>Receive budget threshold alerts</FormControl.Label>
          </FormControl>
        </div>
      </div>
      {alertEnabled && (
        <Box sx={{paddingBottom: 2, paddingTop: 3}}>
          <Heading as="h2" sx={{fontSize: 1}}>
            Alert recipients
          </Heading>
          <span>
            These people will get notified via email if this budget has reached the specific threshold. Billing managers
            and email recipients will receive all budget alert threshold emails by default.
          </span>
          <Suspense fallback={<Spinner size="small" />}>
            {!loading && (
              <OrgUserPicker
                orgName={orgName}
                initialRecipients={initialRecipients}
                onSelectionChange={handleRecipientsChange}
              />
            )}
          </Suspense>
        </Box>
      )}
    </>
  )
}
