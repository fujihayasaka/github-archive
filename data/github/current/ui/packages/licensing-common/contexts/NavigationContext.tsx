import type {PropsWithChildren} from 'react'
import {createContext, useContext, useMemo} from 'react'

interface NavigationContextState {
  basePath: string
  enterpriseContactUrl: string
  isStafftools: boolean
  isTeams: boolean
  slug: string
}

const NavigationContext = createContext<NavigationContextState>({
  basePath: '',
  enterpriseContactUrl: '',
  isStafftools: false,
  isTeams: false,
  slug: '',
})

interface NavigationProviderProps {
  enterpriseContactUrl: string
  isStafftools?: boolean
  isTeams?: boolean
  slug: string
}

export const NavigationContextProvider = ({
  children,
  enterpriseContactUrl,
  isStafftools = false,
  isTeams = false,
  slug,
}: PropsWithChildren<NavigationProviderProps>) => {
  let basePath = isStafftools ? `/stafftools/enterprises/${slug}` : `/enterprises/${slug}`
  if (isTeams) {
    basePath = isStafftools ? `/stafftools/users/${slug}` : `/organizations/${slug}/settings`
  }
  const contextValue = useMemo<NavigationContextState>(
    () => ({basePath, enterpriseContactUrl, isStafftools, isTeams, slug}),
    [basePath, enterpriseContactUrl, isStafftools, isTeams, slug],
  )
  return <NavigationContext.Provider value={contextValue}>{children}</NavigationContext.Provider>
}

export const useNavigation = () => {
  const context = useContext(NavigationContext)
  if (!context) {
    throw new Error('useNavigation must be used within a NavigationProvider')
  }
  return context
}
