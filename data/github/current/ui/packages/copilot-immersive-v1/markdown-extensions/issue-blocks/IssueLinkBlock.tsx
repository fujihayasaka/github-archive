import {useChatStateValue} from '@github-ui/copilot-chat/CopilotChatContext'
import type {
  APIResponseReference,
  CopilotChatMessage,
  CopilotChatReference,
  IssueAPIReference,
  IssueReference,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Link} from '@primer/react'
import {useEffect} from 'react'

import {useContentPreview} from '../../components/ContentPreview/ContentPreviewContext'
import {useContentPreviewBlockContext} from '../ContentPreviewBlockContext'

/**
 * Extract the issue title from the message's references.
 */
function extractIssueTitle(
  messages: CopilotChatMessage[],
  messageId: string,
  owner: string | undefined,
  repo: string | undefined,
  number: number,
): string {
  const fallbackTitle = `Issue #${number}`
  if (!owner || !repo || !number || isNaN(number)) return fallbackTitle

  const message = messages.find(m => m.id === messageId)
  const references = message?.references

  // try to extract the title from an issue reference
  const issueReference = references?.find(
    (reference: CopilotChatReference): reference is IssueReference =>
      reference.type === 'issue' &&
      reference.number === number &&
      reference.repository.name === repo &&
      reference.repository.owner === owner,
  )
  const title = issueReference?.title
  if (title) return title

  // try to extract the title from an issue API response reference
  const issueApiReference = references?.find(
    (reference: CopilotChatReference): reference is APIResponseReference =>
      reference.type === 'api-response' &&
      reference.resourceType === 'Issue' &&
      reference.repo === `${owner}/${repo}` &&
      reference.data.number === number,
  )
  const referenceData = issueApiReference?.data as IssueAPIReference
  return referenceData?.title ?? fallbackTitle
}

export interface IssueLinkBlockProps {
  owner: string
  repo: string
  issueNumber: string
  href: string
  children: string
}

export function IssueLinkBlock({owner, repo, issueNumber, href, children}: IssueLinkBlockProps) {
  const {updateItem, openItem, openPreviewPane} = useContentPreview()
  const {messageId} = useContentPreviewBlockContext()
  const number = Number(issueNumber)

  const messages = useChatStateValue('messages')
  const title = extractIssueTitle(messages, messageId, owner, repo, number)

  const issueLink = href

  const id = `issue:${owner}/${repo}/${number}` as const

  useEffect(() => {
    if (owner && repo)
      updateItem({
        messageId,
        name: title,
        number,
        owner,
        repo,
        id,
        type: 'issue',
      })
  }, [id, messageId, number, owner, repo, title, updateItem])

  return (
    <Link
      href={issueLink}
      onClick={e => {
        // allow users to open the link in a new tab with the meta key
        if (e.metaKey || e.ctrlKey) return

        openItem(id)
        openPreviewPane()

        sendEvent('dotcom_chat.activate', {target: 'BROWSER_ISSUE_OPENED', mode: 'immersive'})

        e.preventDefault()
      }}
      target="_blank"
      rel="noreferrer"
    >
      {children}
    </Link>
  )
}
