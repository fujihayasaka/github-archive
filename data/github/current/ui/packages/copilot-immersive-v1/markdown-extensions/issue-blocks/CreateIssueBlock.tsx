import {sendEvent} from '@github-ui/hydro-analytics'
import {Link} from '@primer/react'
import {load} from 'js-yaml'
import {useEffect, useState} from 'react'

import {useContentPreview} from '../../components/ContentPreview/ContentPreviewContext'
import {useContentPreviewBlockContext} from '../ContentPreviewBlockContext'

export const issueOwnerAttribute = 'data-issue-owner'
export const issueRepoAttribute = 'data-issue-repo'
export const issueTitleAttribute = 'data-issue-title'
export const createIssueBlockAttribute = 'data-create-issue-block'

export const issueLinkBlockAttributes = [issueOwnerAttribute, issueRepoAttribute, issueTitleAttribute]

export interface Issue {
  title?: string
  body?: string
  labels?: string[]
  assignees?: string[]
  repository?: string
  type?: string
  projects?: string[]
}

const Issue = {
  /** Being extremely defensive about the types here allows us to safely handle partial data and bad model results. */
  fromUnknown: (data: unknown): Issue => {
    if (typeof data !== 'object' || data === null) return {}

    // there's probably a library that could do this less tediously
    const item: Issue = {}

    if ('title' in data && typeof data.title === 'string') item.title = data.title
    if ('body' in data && typeof data.body === 'string') item.body = data.body
    if ('labels' in data && Array.isArray(data.labels)) item.labels = data.labels.filter(el => typeof el === 'string')
    if ('assignees' in data && Array.isArray(data.assignees))
      item.assignees = data.assignees.filter(el => typeof el === 'string')
    if ('repository' in data && typeof data.repository === 'string') item.repository = data.repository
    if ('type' in data && typeof data.type === 'string') item.type = data.type
    if ('projects' in data && Array.isArray(data.projects))
      item.projects = data.projects.filter(el => typeof el === 'string')

    return item
  },
}

export interface CreateIssueBlockProps {
  children: string
}

const parseIssueData = (yaml: string) => {
  try {
    const result = load(yaml)
    if (typeof result === 'object' && result !== null) return Issue.fromUnknown(result)
    return null
  } catch {
    return null
  }
}

export function CreateIssueBlock({children}: CreateIssueBlockProps) {
  const [issue, setIssue] = useState<Issue>(() => parseIssueData(children) ?? {})

  // Ignore intermediate updates with bad data (partially streamed YAML)
  useEffect(() => setIssue(lastParsedData => parseIssueData(children) ?? lastParsedData), [children])

  const {updateItem, openItem, openPreviewPane} = useContentPreview()
  const {messageId} = useContentPreviewBlockContext()

  useEffect(() => sendEvent('dotcom_chat.activate', {target: 'ISSUE_CREATE_BLOCK_RENDERED', mode: 'immersive'}), [])

  const issueLink = '#'

  const id = `issue:${issue.repository ?? ''}` as const
  const [owner, repo] = issue.repository?.split('/') ?? []

  useEffect(() => {
    if (owner && repo)
      updateItem({
        messageId,
        name: issue.title || '',
        body: issue.body,
        owner,
        repo,
        id,
        type: 'new-issue',
      })
  }, [id, issue.body, issue.repository, issue.title, messageId, owner, repo, updateItem])

  return (
    <Link
      href={issueLink}
      onClick={e => {
        // allow users to open the link in a new tab with the meta key
        if (e.metaKey || e.ctrlKey) return

        openItem(id)
        openPreviewPane()

        sendEvent('dotcom_chat.activate', {target: 'BROWSER_CREATE_ISSUE_OPENED', mode: 'immersive'})

        e.preventDefault()
      }}
      target="_blank"
      rel="noreferrer"
    >
      {issue.title}
    </Link>
  )
}
