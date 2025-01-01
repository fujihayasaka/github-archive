import {AgentsPlugin} from '@github-ui/agent-sessions'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {ImmersivePluginsProvider} from '@github-ui/copilot-chat/plugin/registry'
import {isDocset, makeDocsetReference} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {PipesPlugin} from '@github-ui/copilot-loops'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
// eslint-disable-next-line no-restricted-imports
import {ScreenSizeProvider} from '@github-ui/screen-size'
import {SparkPlugin} from '@github-ui/spark'
import {useMemo} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'

import {ContentPreviewProvider} from '../components/ContentPreview/ContentPreviewContext'
import {ImmersiveDisabled} from '../components/ImmersiveDisabled'
import {Layout} from '../components/Layout'
import {useRoutePluginId, useSyncPluginToRoute} from '../hooks/use-route-plugin-id'
import {useRouteThreadId} from '../hooks/use-route-thread-id'
import {useRoutedThreads} from '../hooks/use-routed-threads'
import type {CopilotImmersivePayload} from './payloads'

const environment = relayEnvironmentWithMissingFieldHandlerForNode()

export function CopilotImmersive() {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <CopilotImmersiveNoRelay />
    </RelayEnvironmentProvider>
  )
}

// This component is used to render the immersive experience without the relay environment
// This is useful for testing purposes when the relay environment is provided by renderRelay test helper
export function CopilotImmersiveNoRelay() {
  const payload = useAppPayload<CopilotImmersivePayload>()
  const copilotSetting = payload?.copilotChatSettingEnabled

  if (copilotSetting) {
    return (
      <CopilotImmersiveProviders>
        <Immersive />
      </CopilotImmersiveProviders>
    )
  } else {
    return <ImmersiveDisabled />
  }
}

function CopilotImmersiveProviders({children}: React.PropsWithChildren) {
  const payload = useAppPayload<CopilotImmersivePayload>()
  const threadId = useRouteThreadId()
  const {refs, topic} = useMemo(() => {
    const requestedTopic = payload.requestedTopic
    if (isDocset(requestedTopic)) {
      return {refs: [makeDocsetReference(requestedTopic)], topic: undefined}
    } else if (payload.reference) {
      return {refs: [payload.reference], topic: requestedTopic}
    } else {
      return {refs: [], topic: requestedTopic}
    }
  }, [payload.requestedTopic, payload.reference])

  const plugins = useMemo(() => {
    const pluginsList: ImmersivePlugin[] = []

    if (copilotFeatureFlags.pipesPlugin) {
      pluginsList.push(
        new PipesPlugin(
          payload.apiURL,
          payload.graphqlApiUrl,
          payload.ssoOrganizations.map(o => o.id),
          payload.previewUrl,
          payload.realIp,
        ),
      )
    }

    if (copilotFeatureFlags.workbenchPlugin) {
      pluginsList.push(new SparkPlugin())
    }

    if (copilotFeatureFlags.agentSessionsEnabled) {
      pluginsList.push(new AgentsPlugin())
    }

    return pluginsList
  }, [payload.apiURL, payload.graphqlApiUrl, payload.realIp, payload.ssoOrganizations, payload.previewUrl])

  const pluginId = useRoutePluginId(plugins)

  return (
    <ScreenSizeProvider>
      <ImmersivePluginsProvider plugins={plugins}>
        <CopilotChatProvider
          workerPath={payload.searchWorkerFilePath}
          threadId={threadId}
          pluginId={pluginId}
          refs={refs}
          mode="immersive"
          topic={topic}
          ssoOrganizations={payload.ssoOrganizations}
          copilotUpsellBannerDismissed={payload.copilotUpsellBannerDismissed}
          copilotChatPayload={payload}
        >
          <ContentPreviewProvider>{children}</ContentPreviewProvider>
        </CopilotChatProvider>
      </ImmersivePluginsProvider>
    </ScreenSizeProvider>
  )
}

function Immersive() {
  useRoutedThreads()
  useSyncPluginToRoute()

  return <Layout />
}
