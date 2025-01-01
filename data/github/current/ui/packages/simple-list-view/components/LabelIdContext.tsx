import {createContext, type ReactNode, useContext} from 'react'

const LabelIdContext = createContext<string | undefined>(undefined)

type LabelIdProviderProps = {
  children: ReactNode
  value: string
}

export const LabelIdProvider = ({children, value}: LabelIdProviderProps) => (
  <LabelIdContext.Provider value={value}>{children}</LabelIdContext.Provider>
)

export const useLabelId = () => {
  const context = useContext(LabelIdContext)
  if (!context) throw new Error('useLabelId must be used with LabelIdProvider.')
  return context
}
