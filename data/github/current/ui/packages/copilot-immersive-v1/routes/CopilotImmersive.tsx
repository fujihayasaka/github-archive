import {isDocset, makeDocsetReference} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {ScreenSizeProvider} from '@github-ui/screen-size'
import {QueryClient, QueryClientProvider} from '@tanstack/react-query'
import {useEffect, useMemo} from 'react'

import {ContentPreviewProvider} from '../components/ContentPreview/ContentPreviewProvider'
import {Layout} from '../components/Layout'
import {useRoutedThreads} from '../hooks/use-routed-threads'
import type {CopilotImmersivePayload} from './payloads'

export function CopilotImmersive() {
  // THIS IS A HACK: The staff bar is extremely annoying in the Copilot immersive experience for Hubbers because
  // it causes the page to scroll by the height of the staff bar. However, it shouldn't scroll; the input should
  // stick to the bottom, and the message container should overflow and scroll. Disabling the staff bar in a
  // different view every time is not an option. Unfortunately, there is no good way to determine the height of
  // the content. Currently, we subtract the global nav height from the content (`calc(100vh - 64px)`) for all
  // React apps to ensure there is no scrolling for users (or when the staff bar is turned off). Ideally, we
  // would create a flex wrapper for the entire page, which would allow us to better control the content. There
  // are multiple non-ideal ways to achieve this, and this approach seems to be the quickest one.
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
    <CopilotImmersiveProviders>
      <Immersive />
    </CopilotImmersiveProviders>
  )
}

const queryClient = new QueryClient()

function CopilotImmersiveProviders({children}: React.PropsWithChildren) {
  const payload = useRoutePayload<CopilotImmersivePayload>()
  const {refs, topic} = useMemo(() => {
    const requestedTopic = payload.requestedTopic
    if (isDocset(requestedTopic)) {
      return {refs: [makeDocsetReference(requestedTopic)], topic: undefined}
    } else {
      return {refs: [], topic: requestedTopic}
    }
  }, [payload.requestedTopic])

  return (
    <ContentPreviewProvider>
      <ScreenSizeProvider>
        <QueryClientProvider client={queryClient}>
          <CopilotChatProvider
            login={payload.currentUserLogin}
            apiURL={payload.apiURL}
            workerPath={payload.searchWorkerFilePath}
            threadId={payload.threadID}
            refs={refs}
            mode="immersive"
            topic={topic}
            ssoOrganizations={payload.ssoOrganizations}
            renderKnowledgeBases={payload.renderKnowledgeBases}
            renderAttachKnowledgeBaseHerePopover={payload.renderAttachKnowledgeBaseHerePopover}
            renderKnowledgeBaseAttachedToChatPopover={payload.renderKnowledgeBaseAttachedToChatPopover}
            customInstructions={payload.customInstructions}
            agentsPath={payload.agentsPath}
            optedInToUserFeedback={payload.optedInToUserFeedback}
            reviewLab={payload.reviewLab}
          >
            {children}
          </CopilotChatProvider>
        </QueryClientProvider>
      </ScreenSizeProvider>
    </ContentPreviewProvider>
  )
}

function Immersive() {
  useRoutedThreads()

  return <Layout />
}
