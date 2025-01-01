import {type PropsWithChildren, useMemo} from 'react'

import {RoutesContext, type RoutesContextType} from './routes-context'

export function RoutesContextProvider({routes, children}: PropsWithChildren<RoutesContextType>) {
  const appContextProviderValue = useMemo(() => ({routes}), [routes])
  return <RoutesContext.Provider value={appContextProviderValue}>{children}</RoutesContext.Provider>
}
