import {useEffect, useState} from 'react'
import type {ZuoraEmission, EmissionDate} from '../../types/zuora-emissions'
import {getZuoraEmissionsRequest} from '../../services/zuora_emissions'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {ERRORS} from '../../constants'
import {RequestState} from '../../enums'

type UseZuoraEmissionsParams = {
  enterpriseSlug: string
  emissionDate: EmissionDate
}
function useZuoraEmissions({enterpriseSlug, emissionDate}: UseZuoraEmissionsParams) {
  const [zuoraEmissions, setZuoraEmissions] = useState<ZuoraEmission[]>([])
  const [requestState, setRequestState] = useState<RequestState>(RequestState.INIT)
  const {addToast} = useToastContext()

  useEffect(() => {
    const getZuoraEmissions = async () => {
      if (!enterpriseSlug || !emissionDate) {
        return
      }
      setRequestState(RequestState.LOADING)
      try {
        const response = await getZuoraEmissionsRequest(enterpriseSlug, emissionDate)
        if (response.statusCode === 200) {
          setZuoraEmissions(response.payload.zuoraEmissions)
          setRequestState(RequestState.IDLE)
        } else {
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.QUERY_ZUORA_EMISSIONS_ERROR,
          })
          setRequestState(RequestState.ERROR)
        }
      } catch {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: ERRORS.QUERY_ZUORA_EMISSIONS_ERROR,
        })
        setRequestState(RequestState.ERROR)
      }
    }
    setZuoraEmissions([])
    getZuoraEmissions()
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [emissionDate])

  return {zuoraEmissions, requestState}
}

export default useZuoraEmissions
