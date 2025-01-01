import type {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import type {DiffHunkReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {formatPatch} from 'diff'

import {assertDefined} from './asserts'
import type {ChangedFile} from './workspace-editor-types'

export type AgentResponse = {
  choices: Array<{message: Message}>
  type: undefined
}

type Message = {
  role: string
  content: string
}

type DiffHunkAgentReference = {
  type: 'github.diff-hunk'
  data: DiffHunkReference
}

type ValidatedCommitMessage = {
  commitMessage: string
  description?: string
}

const MAX_COMMIT_MESSAGE_LENGTH = 72
const ELLIPSES = '...'

export async function handleStreamingMessage(
  streamer: CopilotChatMessageStreamer<AgentResponse>,
): Promise<AgentResponse> {
  const messages: AgentResponse[] = []

  for await (const message of streamer.stream()) {
    messages.push(message)
  }

  if (messages.length === 0) {
    throw new Error('No messages found in stream')
  }

  if (messages.length > 1) {
    throw new Error('More than one message found in stream')
  }

  const message = messages[0]!
  return message
}

export function validateAndExtractCommitMessage(agentResponse: AgentResponse): ValidatedCommitMessage | undefined {
  const commitMessageResponse = agentResponse?.choices?.[0]?.message

  assertDefined(commitMessageResponse, 'No message found in agent response')
  assertDefined(commitMessageResponse.content, 'No content found in commit message')

  if (commitMessageResponse.content.toLowerCase() === 'not enough context') return

  if (commitMessageResponse.content.length > MAX_COMMIT_MESSAGE_LENGTH) {
    return {
      commitMessage: `${commitMessageResponse.content.substring(
        0,
        MAX_COMMIT_MESSAGE_LENGTH - ELLIPSES.length,
      )}${ELLIPSES}`,
      description: `${ELLIPSES}${commitMessageResponse.content.substring(MAX_COMMIT_MESSAGE_LENGTH - ELLIPSES.length)}`,
    }
  }

  return {commitMessage: commitMessageResponse.content}
}

export function formatChangedFilesAsDiffs(files: ChangedFile[]): DiffHunkAgentReference[] {
  return files.map(file => {
    return {
      type: 'github.diff-hunk',
      data: {
        type: 'diff-hunk',
        changeReference: '',
        fileName: file.path,
        headerContext: '',
        diff: formatPatch(file.patch),
      },
    }
  })
}
