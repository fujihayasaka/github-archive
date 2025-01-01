import {verifiedFetch} from '@github-ui/verified-fetch'
import type {ApiMarkdownSubject, SubjectType} from './types'
import {useCallback} from 'react'
import type {SafeHTMLString} from '@github-ui/safe-html'

interface MarkdownPreviewRequest {
  text: string
  issue: string
  repository: string
  project: string
  subjectType?: 'Issue' | 'PullRequest' | 'Project'
  path?: string
  lineNumber?: number
  startCommitOid?: string
  endCommitOid?: string
  baseCommitOid?: string
  startLineNumber?: number
  subject?: number
}

/**
 * Fetches a markdown preview for the given text.
 * We can brand the returned html as a SafeHTMLString because it is generated
 * by GitHub and we trust it.
 */
async function tryGetPreview({
  text,
  issue,
  repository,
  project,
  subjectType,
  path,
  lineNumber,
  startCommitOid,
  endCommitOid,
  baseCommitOid,
  subject,
  startLineNumber,
}: MarkdownPreviewRequest): Promise<SafeHTMLString> {
  const formData = new FormData()
  formData.append('text', text)
  formData.append('issue', issue)
  formData.append('repository', repository)
  formData.append('project', project)
  if (path) formData.append('path', path)
  if (lineNumber) formData.append('line_number', lineNumber.toString())
  if (startCommitOid) formData.append('start_commit_oid', startCommitOid)
  if (endCommitOid) formData.append('end_commit_oid', endCommitOid)
  if (baseCommitOid) formData.append('base_commit_oid', baseCommitOid)
  if (subject) formData.append('subject', subject.toString())
  if (startLineNumber) formData.append('start_line_number', startLineNumber.toString())

  if (subjectType) {
    formData.append('subject_type', subjectType)
  }
  const response = await verifiedFetch('/preview', {body: formData, method: 'POST'})
  if (!response.ok) {
    return Promise.resolve('Markdown preview unavailable' as SafeHTMLString)
  }
  const htmlText = await response.text()
  return Promise.resolve(htmlText as SafeHTMLString)
}

export function useGetPreview({
  subjectId,
  subjectType,
  subject,
  subjectRepoId,
  lineNumber,
  path,
  startCommitOid,
  startLineNumber,
  endCommitOid,
  baseCommitOid,
}: Partial<ApiMarkdownSubject> & {
  lineNumber?: number
  path?: string
  startCommitOid?: string
  endCommitOid?: string
  baseCommitOid?: string
  startLineNumber?: number
  subject?: number
}) {
  return useCallback(
    async (body: string) => {
      return tryGetPreview({
        text: body,
        issue: subjectId?.toString() ?? '',
        repository: subjectRepoId?.toString() ?? '',
        project: subjectId?.toString() ?? '',
        subjectType: resolvePreviewSubjectType(subjectType),
        subject,
        lineNumber,
        path,
        startCommitOid,
        endCommitOid,
        baseCommitOid,
        startLineNumber,
      })
    },
    [
      subjectId,
      subjectRepoId,
      subjectType,
      subject,
      lineNumber,
      path,
      startCommitOid,
      startLineNumber,
      endCommitOid,
      baseCommitOid,
    ],
  )
}

function resolvePreviewSubjectType(subjectType: SubjectType | undefined): MarkdownPreviewRequest['subjectType'] {
  switch (subjectType) {
    case 'issue':
      return 'Issue'
    case 'pull_request':
      return 'PullRequest'
    case 'project':
      return 'Project'
    default:
      return undefined
  }
}
