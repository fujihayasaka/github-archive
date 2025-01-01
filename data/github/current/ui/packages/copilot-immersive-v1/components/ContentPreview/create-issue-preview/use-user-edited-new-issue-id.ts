import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'

import type {DraftIssue} from '../content-preview-types'

export function useUserEditedNewIssueId(tag: string): DraftIssue['id'] {
  const {messages} = useChatState()
  return `new-issue:${tag}#${messages.length}` // messages.length represents the next user message index
}
