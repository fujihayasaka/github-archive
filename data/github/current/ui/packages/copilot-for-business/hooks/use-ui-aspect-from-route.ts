import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {CopilotForBusinessPoliciesPayload} from '../types'

/**
 * Lets pick a certain `aspect` from the payload. An aspect is an isolated piece of data from the route payload.
 * Allowing us to separate the concerns, so we can iterate on them independently, and confidently.
 */
export function useUIAspectFromRoute<T extends keyof CopilotForBusinessPoliciesPayload>(
  aspect: T,
): CopilotForBusinessPoliciesPayload[T] {
  return useRoutePayload<CopilotForBusinessPoliciesPayload>()[aspect]
}
