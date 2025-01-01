import {CreateIssueForm as InnerCreateIssueForm} from '@github-ui/issue-create/CreateIssueForm'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {OnCreateProps} from '@github-ui/issue-create/Model'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {IssueViewerLoading} from '@github-ui/issue-viewer/IssueViewerLoading'
import {noop} from '@github-ui/noop'
import {useCallback, useEffect, useRef, useState} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useDraftIssueAssignees} from './use-draft-issue-assignees'
import {useDraftIssueLabels} from './use-draft-issue-labels'
import {useDraftIssueMilestone} from './use-draft-issue-milestone'
import {useDraftIssueProjects} from './use-draft-issue-projects'
import {useDraftIssueType} from './use-draft-issue-type'

type CreateIssueFormProps = {
  draftIssue: DraftIssue
  onCreate?: (issue: OnCreateProps['issue']) => void
  onChange?: (issue: Partial<DraftIssue>) => void
  onClose?: () => void
  onBeforeCreate?: (issueBody: string) => Promise<string>
}

export function CreateIssueForm({draftIssue, onCreate, onChange, onClose, onBeforeCreate}: CreateIssueFormProps) {
  const {name: initTitle, body: initDescription = ''} = draftIssue

  const issueFormRef = useRef<IssueFormRef>(null)
  const {repository, clearSessionData} = useIssueCreateDataContext()
  const [title, setTitle] = useState(initTitle)
  const [description, setDescription] = useState(initDescription)

  const onClearSession = useCallback(() => {
    // Copied from ui/packages/issue-create/hooks/use-safe-close.ts
    clearSessionData()
    issueFormRef.current?.clearSessionStorage()
  }, [clearSessionData])

  const onClearAndClose = useCallback(() => {
    onClearSession()
    onClose?.()
  }, [onClearSession, onClose])

  useEffect(() => {
    setTitle(initTitle)
    setDescription(initDescription)
  }, [initDescription, initTitle])

  useDraftIssueAssignees(draftIssue)
  useDraftIssueLabels(draftIssue)
  useDraftIssueType(draftIssue)
  useDraftIssueMilestone(draftIssue)
  useDraftIssueProjects(draftIssue)

  if (repository == null) {
    return <IssueViewerLoading optionConfig={{useViewportQueries: false}} />
  }

  return (
    <InnerCreateIssueForm
      repository={repository}
      title={title}
      body={description}
      setTitle={newTitle => {
        setTitle(newTitle)
        onChange?.({name: newTitle})
      }}
      setBody={newDescription => {
        setDescription(newDescription)
        onChange?.({body: newDescription})
      }}
      clearOnCreate={onClearAndClose}
      issueFormRef={issueFormRef}
      onCreateSuccess={({issue}: OnCreateProps) => onCreate?.(issue)}
      onCreateError={noop}
      onCancel={onClearAndClose}
      onBeforeCreate={onBeforeCreate}
    />
  )
}
