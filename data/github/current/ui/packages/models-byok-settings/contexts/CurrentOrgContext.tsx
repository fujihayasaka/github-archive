import {createContext, useContext} from 'react'
import invariant from 'tiny-invariant'

const CurrentOrgContext = createContext<string | null>(null)

export const CurrentOrgProvider = CurrentOrgContext.Provider

export function useCurrentOrg() {
  const org = useContext(CurrentOrgContext)
  invariant(org, 'useCurrentOrg must be used within a CurrentOrgProvider')
  return org
}
