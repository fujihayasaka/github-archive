import type {AppListing} from '@github-ui/marketplace-common'
import type {PlanInfo, Plan} from '../../../../types'
import {createContext, useContext, useMemo, useState, type PropsWithChildren} from 'react'
import {useCSRFToken} from '@github-ui/use-csrf-token'

type PlanFormContextType = {
  planInfo: PlanInfo
  listing: AppListing
  plan: Plan
  seatQuantity: number
  setSeatQuantity: (quantity: number) => void
  selectedAccount?: string
  setSelectedAccount: (account: string) => void
  canReinstall: boolean
  skipOrderReview: boolean
  authToken?: string
}

const PlanFormContext = createContext<PlanFormContextType | null>(null)

export function usePlanForm() {
  const context = useContext(PlanFormContext)
  if (!context) {
    throw new Error('usePlanForm must be used within the PlanForm component')
  }
  return context
}

type PlanFormProviderProps = Omit<
  PropsWithChildren<PlanFormContextType>,
  'seatQuantity' | 'setSeatQuantity' | 'authToken'
>

export default function PlanFormProvider({children, ...props}: PlanFormProviderProps) {
  const [seatQuantity, setSeatQuantity] = useState(props.planInfo.orderPreview?.quantity || 1)

  const authToken = useCSRFToken(
    `/marketplace/${props.listing.slug}/order/${props.plan.id}${props.canReinstall ? '/upgrade' : ''}`,
    'post',
  )

  const value = useMemo(() => {
    return {seatQuantity, setSeatQuantity, authToken, ...props}
  }, [seatQuantity, setSeatQuantity, authToken, props])

  return <PlanFormContext.Provider value={value}>{children}</PlanFormContext.Provider>
}
