import {useAppPayload} from '@github-ui/react-core/use-app-payload'

import type {CopilotImmersivePayload} from '../routes/payloads'

export function useFigmaAuthUrl(): string | undefined {
  const {figmaAuthUrl} = useAppPayload<CopilotImmersivePayload>()

  if (!figmaAuthUrl) return undefined

  const url = new URL(figmaAuthUrl, location.origin)
  // this needs to be a relative URL because the server won't redirect to an absolute URL
  url.searchParams.set('return_url', location.pathname + location.search)
  return url.toString()
}
