import {useState} from 'react'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'

import useRequest from '../use-request'

import {ERRORS} from '../../constants'
import {BUDGETS_ROUTE} from '../../routes'

import type {Budget} from '../../types/budgets'
import {RequestState} from '../../enums'

function useBudgetsPage() {
  const [budgets, setBudgets] = useState<Budget[]>([])
  const [requestState, setRequestState] = useState<RequestState>(RequestState.INIT)
  const {addToast} = useToastContext()

  useRequest({
    route: BUDGETS_ROUTE,
    onStart: () => {
      setBudgets([])
      setRequestState(RequestState.LOADING)
    },
    onSuccess: response => {
      setBudgets(response.data.payload.budgets)
      setRequestState(RequestState.IDLE)
    },
    onError: () => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: ERRORS.QUERY_BUDGETS_ERROR,
      })
    },
  })

  /** removes budget from state with a given uuid */
  function deleteBudgetFromPage(uuid: string) {
    const deleteIndex = budgets.findIndex(b => b.uuid === uuid)
    const updatedBudgets = [...budgets]

    updatedBudgets.splice(deleteIndex, 1)

    setBudgets(updatedBudgets)
  }

  return {budgets, deleteBudgetFromPage, requestState}
}

export default useBudgetsPage
