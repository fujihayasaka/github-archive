import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {type CopilotChatReference, NullMessageId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {OnCreateProps} from '@github-ui/issue-create/Model'
import {useCallback} from 'react'

import type {TimelineEventTextReference} from '../../TimelineEvents'
import {makeReferenceFromVersionedItem} from '../content-preview-types'
import {useContentPreview} from '../ContentPreviewContext'
import {useUserEditedNewIssueId} from './use-user-edited-new-issue-id'

export function useOnCreateCallback({tag}: {tag: string}) {
  const state = useChatState()
  const manager = useChatManager()
  const {items, updateItem, openItem, closeItem, openPreviewPane} = useContentPreview()
  const userEditedNewIssueId = useUserEditedNewIssueId(tag)

  return useCallback(
    async (issue: OnCreateProps['issue']) => {
      sendEvent('dotcom_chat.activate', {
        target: 'BROWSER_ISSUE_CREATED',
        mode: 'immersive',
        threadId: getSelectedThread(state)?.id,
        repositoryId: issue.repository.databaseId,
        issueNumber: issue.number,
        chatReferrer: document.referrer,
      })

      const number = issue.number
      const owner = issue.repository.owner.login
      const repo = issue.repository.name
      const title = issue.title
      const id = `issue:${owner}/${repo}/${number}` as const

      // Create the issue in the content preview context
      // This happens first so that we don't have to wait for the API call to complete
      // to show the issue in the preview pane
      updateItem({
        id,
        messageId: NullMessageId,
        name: title,
        owner,
        repo,
        number,
        href: issue.url,
        type: 'issue',
      })

      // Make sure to close the tab for the edited draft, then show final issue in the preview pane
      closeItem(userEditedNewIssueId)
      openItem(id)
      openPreviewPane()

      const instructions: TimelineEventTextReference = {
        type: 'text',
        name: `timeline-event: {"type": "issue-created", "markdownContent": "Issue saved to [${owner}/${repo}#${number}](${issue.url})"}`,
        text:
          'Fetch the issue details and return them in a code block with YAML following this example format:\n' +
          '```list type="issue"\n' +
          'data:\n' +
          `- url: ${issue.url}\n` +
          '  state: "open"\n' +
          '  draft: false\n' +
          `  title: "${title}"\n` +
          `  number: ${number}\n` +
          `  author: ${state.currentUserLogin}\n` +
          '  created_at: "2025-03-27T12:00:00Z"\n' +
          '  closed_at: "2025-03-27T12:00:00Z"\n' +
          '  labels:\n' +
          '  - name: "bug"\n' +
          '  - name: "good first issue"\n' +
          '```',
      }

      const references: CopilotChatReference[] = [instructions]
      const item = items.get(userEditedNewIssueId)
      if (item?.type === 'new-issue') references.push(makeReferenceFromVersionedItem(item))

      await manager.sendChatMessage({
        thread: getSelectedThread(state),
        content: `Saved the issue to [${owner}/${repo}#${number}](${issue.url})`,
        references,
        topic: state.currentTopic,
        context: state.context,
        customInstructions: state.customInstructions,
        model: state.model,
      })
    },
    [userEditedNewIssueId, manager, state, items, openPreviewPane, openItem, updateItem, closeItem],
  )
}
