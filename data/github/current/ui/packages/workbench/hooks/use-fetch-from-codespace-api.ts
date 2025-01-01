import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useCallback, useMemo} from 'react'

import {useCodespaceContext} from '../contexts/CodespaceContext'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {SparkAuthTokenProvider} from '../utilities/auth-token-provider'

export function useFetchFromCodespaceApi() {
  const {codespaceData} = useCodespaceContext()
  const {
    copilot: {ssoOrganizations},
  } = useRoutePayload<WorkbenchRoutePayload>()
  const {friendlyName} = codespaceData.codespaceInfo?.environment_data || {}
  const domain = codespaceData.remoteProvider?.tunnelProps.domain ?? 'app.github.dev'
  const {codespaceState} = codespaceData
  const tunnelToken =
    codespaceData.codespaceInfo?.environment_data.connection.tunnelProperties?.connectAccessToken || ''

  const authTokenProvider = useMemo(() => {
    if (copilotFeatureFlags.sparkAuthTokenEndpoint) {
      return new SparkAuthTokenProvider(ssoOrganizations.map(org => org.id))
    } else {
      return new CopilotAuthTokenProvider(ssoOrganizations.map(org => org.id))
    }
  }, [ssoOrganizations])

  const fetchFromCodespaceApi = useCallback(
    async (path: string, init?: RequestInit): Promise<Response> => {
      if (!friendlyName || !domain || !tunnelToken || codespaceState !== 'ready') {
        throw new Error('Codespace connection information is not available')
      }

      let token: AuthToken
      if (copilotFeatureFlags.sparkAuthTokenEndpoint) {
        token = await authTokenProvider.getAuthToken()
      } else {
        token = await authTokenProvider.getTokenForSpark()
      }

      const baseUrl = `https://${friendlyName}-9000.${domain}`
      const normalizedPath = path.startsWith('/') ? path : `/${path}`
      const url = `${baseUrl}${normalizedPath}`

      let integrationId: string
      if (copilotFeatureFlags.sparkAuthTokenEndpoint) {
        integrationId = process.env.NODE_ENV === 'development' ? 'spark-agent-dev' : 'spark-agent'
      } else {
        integrationId = 'copilot-chat'
      }

      const headers = new Headers(init?.headers)
      headers.set('X-Tunnel-Authorization', `tunnel ${tunnelToken}`)
      headers.set('Authorization', token.authorizationHeaderValue)
      headers.set('copilot-integration-id', integrationId)

      const requestOptions: RequestInit = {
        ...init,
        headers,
      }

      return fetch(url, requestOptions)
    },
    [friendlyName, domain, tunnelToken, codespaceState, authTokenProvider],
  )

  return {fetchFromCodespaceApi}
}
