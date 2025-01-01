import {ChatInput} from '@github-ui/copilot-chat/components/ChatInput'
import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useMemo} from 'react'

import {useFigmaAuthUrl} from '../hooks/use-figma-auth-url'
import {useNavigateToNewThread} from '../hooks/use-navigate-to-new-thread'
import {useOnReferenceSelect} from '../hooks/use-on-reference-select'
import {ChatInputBanners} from './ChatInputBanners'
import {getItemVersionForReference} from './ContentPreview/content-preview-types'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import styles from './Layout.module.css'
import {FreeChatExceededBanner} from './Quota/FreeChatExceededBanner'

interface ChatInputContainerProps {
  textAreaRef: React.RefObject<HTMLTextAreaElement>
  handleUserSubmit: (content: string) => Promise<void>
  nextMessageIndex: number
}

export function ChatInputContainer({textAreaRef, handleUserSubmit, nextMessageIndex}: ChatInputContainerProps) {
  const state = useChatState()
  const {chatQuotaExceeded, isLicensedLimited} = useEntitlement()
  const navigateToNewThread = useNavigateToNewThread()
  const figmaAuthUrl = useFigmaAuthUrl()

  const onInputReferenceSelect = useOnReferenceSelect({messageIndex: nextMessageIndex})

  const {versionedItems, items} = useContentPreview()

  const existingFileNames = useMemo(() => {
    const result = new Set<string>()
    for (const [, item] of items) if (item.type === 'file') result.add(item.name)
    return result
  }, [items])

  const canUseChat = !(isLicensedLimited && chatQuotaExceeded)

  return (
    <div className={styles.chatInputContainer}>
      {canUseChat ? (
        <>
          <ChatInputBanners />
          <ChatInput
            showModelPicker
            onNewThreadSelected={navigateToNewThread}
            textAreaRef={textAreaRef}
            onSubmit={handleUserSubmit}
            isStreaming={!!state.streamingMessage}
            size="large"
            onSelectReference={onInputReferenceSelect}
            getReferenceVersion={reference => getItemVersionForReference(reference, nextMessageIndex, versionedItems)}
            existingFileNames={existingFileNames}
            figmaAuthUrl={figmaAuthUrl}
          />
        </>
      ) : (
        <FreeChatExceededBanner />
      )}
    </div>
  )
}
