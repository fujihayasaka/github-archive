import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {ImmersivePluginsProvider} from '@github-ui/copilot-chat/plugin/registry'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {PipesPlugin} from '@github-ui/copilot-loops'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
// eslint-disable-next-line no-restricted-imports
import {ScreenSizeProvider} from '@github-ui/screen-size'
import {WorkbenchStoreProvider} from '@github-ui/workbench/contexts/WorkbenchStoreContext'
import type React from 'react'
import {useEffect, useMemo} from 'react'

import Layout from '../components/Layout'
import type {SparkPayload} from './payloads'

const Spark: React.FC = () => {
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

  return (
    <CopilotChatProviders>
      <Layout />
    </CopilotChatProviders>
  )
}

function CopilotChatProviders({children}: React.PropsWithChildren) {
  const payload = useAppPayload<SparkPayload>()
  const plugins = useMemo(() => {
    const p: ImmersivePlugin[] = []
    if (copilotFeatureFlags.pipesPlugin) {
      p.push(
        new PipesPlugin(
          payload.apiURL,
          payload.graphqlApiUrl,
          payload.ssoOrganizations.map(o => o.id),
          payload.previewUrl,
          payload.realIp,
        ),
      )
    }

    return p
  }, [payload.apiURL, payload.graphqlApiUrl, payload.realIp, payload.ssoOrganizations, payload.previewUrl])

  return (
    <ScreenSizeProvider>
      <ImmersivePluginsProvider plugins={plugins}>
        <CopilotChatProvider
          workerPath={payload.searchWorkerFilePath}
          threadId={null}
          refs={[]}
          mode="immersive"
          ssoOrganizations={payload.ssoOrganizations}
          copilotUpsellBannerDismissed={payload.copilotUpsellBannerDismissed}
          copilotChatPayload={payload}
        >
          <WorkbenchStoreProvider>{children}</WorkbenchStoreProvider>
        </CopilotChatProvider>
      </ImmersivePluginsProvider>
    </ScreenSizeProvider>
  )
}

export default Spark
