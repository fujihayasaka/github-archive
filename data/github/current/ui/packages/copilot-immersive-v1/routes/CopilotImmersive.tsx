import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {ImmersivePluginsProvider} from '@github-ui/copilot-chat/plugin/registry'
import {isDocset, makeDocsetReference} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {PipesPlugin} from '@github-ui/copilot-pipes'
import {WorkbenchPlugin} from '@github-ui/copilot-workbench'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
// eslint-disable-next-line no-restricted-imports
import {ScreenSizeProvider} from '@github-ui/screen-size'
import {useEffect, useMemo} from 'react'

import {ContentPreviewProvider} from '../components/ContentPreview/ContentPreviewContext'
import {ImmersiveDisabled} from '../components/ImmersiveDisabled'
import {Layout} from '../components/Layout'
import {useRoutePluginId, useSyncPluginToRoute} from '../hooks/use-route-plugin-id'
import {useRouteSpaceId} from '../hooks/use-route-space-id'
import {useRouteThreadId} from '../hooks/use-route-thread-id'
import {useRoutedThreads} from '../hooks/use-routed-threads'
import type {CopilotImmersivePayload} from './payloads'

export function CopilotImmersive() {
  // Hack to hide the staff bar, "temporary" (knock on wood) until there's a better way.
  useEffect(() => {
    const hideStaffBar = () => {
      const staffBar = document.getElementById('serverstats')
      if (staffBar) {
        staffBar.style.display = 'none'
      }
    }

    hideStaffBar()
  }, [])

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
  const copilotSpaceId = useRouteSpaceId()
  const pluginId = useRoutePluginId()
  const {refs, topic} = useMemo(() => {
    const requestedTopic = payload.requestedTopic
    if (isDocset(requestedTopic)) {
      return {refs: [makeDocsetReference(requestedTopic)], topic: undefined}
    } else {
      return {refs: [], topic: requestedTopic}
    }
  }, [payload.requestedTopic])

  const plugins = useMemo(() => {
    const pluginsList: ImmersivePlugin[] = []

    if (copilotFeatureFlags.pipesPlugin) {
      pluginsList.push(
        new PipesPlugin(
          payload.apiURL,
          payload.graphqlApiUrl,
          payload.ssoOrganizations.map(o => o.id),
          payload.realIp,
        ),
      )
    }

    if (copilotFeatureFlags.workbenchPlugin) {
      pluginsList.push(new WorkbenchPlugin())
    }

    return pluginsList
  }, [payload.apiURL, payload.graphqlApiUrl, payload.realIp, payload.ssoOrganizations])

  return (
    <ScreenSizeProvider>
      <ImmersivePluginsProvider plugins={plugins}>
        <CopilotChatProvider
          workerPath={payload.searchWorkerFilePath}
          threadId={threadId}
          copilotSpaceId={copilotSpaceId}
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
