import {createContext, useState, useEffect, useMemo} from 'react'
import type React from 'react'

import {useSearchParams} from '@github-ui/use-navigate'

export const PLAN_TYPES = {
  Individual: 'individual',
  Business: 'business',
} as const

export type PlanType = (typeof PLAN_TYPES)[keyof typeof PLAN_TYPES]

type PlanTypeContextValue = {
  planType: PlanType
  setPlanType: (type: PlanType) => void
}

export const PlanTypeContext = createContext<PlanTypeContextValue>({
  planType: PLAN_TYPES.Individual,
  setPlanType: () => {},
})

type Props = {
  children: React.ReactNode
}

export function PlanTypeContextProvider(props: Props) {
  const {children} = props

  const [searchParams] = useSearchParams()
  const initialPlanType = (searchParams.get('plans') as PlanType) || PLAN_TYPES.Individual
  const [planType, setPlanType] = useState<PlanType>(initialPlanType)

  useEffect(() => {
    const paramPlanType = searchParams.get('plans')

    if (paramPlanType === PLAN_TYPES.Individual || paramPlanType === PLAN_TYPES.Business) {
      setPlanType(paramPlanType)
    }
  }, [searchParams])

  const contextValue = useMemo(() => ({planType, setPlanType}), [planType])

  return <PlanTypeContext.Provider value={contextValue}>{children}</PlanTypeContext.Provider>
}
