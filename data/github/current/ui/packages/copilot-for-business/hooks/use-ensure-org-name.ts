import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {CopilotForBusinessPoliciesPayload} from '../types'
import {useDebugValue} from 'react'

/**
 * Ensures an org name is present. The source of this may change in the future, but allows callsites to remain unaware.
 */
export function useEnsureOrgName() {
  const org_name = useRoutePayload<CopilotForBusinessPoliciesPayload>().org_name
  useDebugValue(org_name)
  return org_name
}
