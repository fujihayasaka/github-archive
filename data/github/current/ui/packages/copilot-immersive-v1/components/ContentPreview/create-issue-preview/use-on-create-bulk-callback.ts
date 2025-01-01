import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {type CopilotChatReference, NullMessageId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {CreatedIssue} from '@github-ui/issue-create/Model'
import {useCallback} from 'react'

import type {TimelineEventTextReference} from '../../TimelineEvents'
import {makeReferenceFromVersionedItem} from '../content-preview-types'
import {useContentPreview} from '../ContentPreviewContext'
import {useUserEditedNewIssueId} from './use-user-edited-new-issue-id'

export type OnCreateBulkProps = {
  parentIssue: CreatedIssue
  createdIssues: CreatedIssue[]
}

export function useOnCreateBulkCallback({tag}: {tag: string}) {
  const state = useChatState()
  const manager = useChatManager()
  const {items, updateItem, openItem, closeItem, openPreviewPane} = useContentPreview()
  const userEditedNewIssueId = useUserEditedNewIssueId(tag)

  return useCallback(
    async ({parentIssue, createdIssues}: OnCreateBulkProps) => {
      sendEvent('dotcom_chat.activate', {
        target: 'BROWSER_ISSUES_BULK_CREATED',
        mode: 'immersive',
        threadId: getSelectedThread(state)?.id,
        repositoryId: parentIssue.repository.databaseId,
      })

      const savedIssuesUrls: string[] = []
      const issuesInstructions = ''
      for (const createdIssue of createdIssues) {
        const number = createdIssue.number
        const owner = createdIssue.repository.owner.login
        const repo = createdIssue.repository.name
        const title = createdIssue.title
        const id = `issue:${owner}/${repo}/${number}` as const

        updateItem({
          id,
          messageId: NullMessageId,
          name: title,
          owner,
          repo,
          number,
          href: createdIssue.url,
          type: 'issue',
        })

        savedIssuesUrls.push(`[${owner}/${repo}#${number}](${createdIssue.url})`)
        issuesInstructions.concat(
          `- url: ${createdIssue.url}\n` +
            '  state: "open"\n' +
            '  draft: false\n' +
            `  title: "${title}"\n` +
            `  number: ${number}\n` +
            `  author: ${state.currentUserLogin}\n` +
            '  created_at: "2025-03-27T12:00:00Z"\n' +
            '  closed_at: "2025-03-27T12:00:00Z"\n' +
            '  labels:\n' +
            '  - name: "bug"\n' +
            '  - name: "good first issue"\n',
        )
      }

      const parentIssueId =
        `issue:${parentIssue.repository.owner.login}/${parentIssue.repository.name}/${parentIssue.number}` as const
      // TODO - for now, only open the parent issue in the preview pane
      closeItem(userEditedNewIssueId)
      openItem(parentIssueId)
      openPreviewPane()

      const instructions: TimelineEventTextReference = {
        type: 'text',
        name: `timeline-event: {"type": "issue-created", "markdownContent": "Creating issues..."}`,
        text:
          `Fetch the details for all saved issues and return them in a code block with YAML following this example format:\n` +
          `\`\`\`list type="issue"\n` +
          `data:\n${issuesInstructions}\`\`\``,
      }

      const references: CopilotChatReference[] = [instructions]
      // TODO - for now, only support attaching a versioned reference if the parent issue was user-edited
      // I think we can leverage the new session storage to fetch edited subissues from within the parent callback.
      const item = items.get(userEditedNewIssueId)
      if (item?.type === 'new-issue') references.push(makeReferenceFromVersionedItem(item))

      await manager.sendChatMessage({
        thread: getSelectedThread(state),
        content: `Saved the issues to ${savedIssuesUrls.join(', ')} in repo ${parentIssue.repository.name}`,
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
