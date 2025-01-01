import {createContext, type PropsWithChildren} from 'react'

export const IsDataRouterEnabledContext = createContext(false)

export function IsDataRouterEnabledContextProvider({enabled, children}: PropsWithChildren<{enabled: boolean}>) {
  return <IsDataRouterEnabledContext.Provider value={enabled}>{children}</IsDataRouterEnabledContext.Provider>
}
