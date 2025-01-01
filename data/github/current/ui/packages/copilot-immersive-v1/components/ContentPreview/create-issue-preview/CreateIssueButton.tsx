import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CreateIssueFooter} from '@github-ui/issue-create/CreateIssueFooter'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {OnCreateProps} from '@github-ui/issue-create/Model'
import type {IssueMetadata} from '@github-ui/issue-create/mutations/create-issue-mutation'
import type {IssueFormRef} from '@github-ui/issue-form/Types'
import {CommandButton} from '@github-ui/ui-commands'
import {useAnalytics} from '@github-ui/use-analytics'
import {Dialog} from '@primer/react'
import React, {useCallback, useRef} from 'react'
import {useRelayEnvironment} from 'react-relay'

import type {DraftIssue} from '../content-preview-types'
import {createBulkIssuesWithHierarchy} from './create-bulk-issues-with-hierarchy'
import type {TreeNode} from './use-draft-issue-tree-map'
import type {OnCreateBulkProps} from './use-on-create-bulk-callback'

export type CreateIssueButtonProps = {
  issueTemplate: string | undefined
  issueNode: TreeNode<DraftIssue> | undefined
  isBulkCreate: boolean
  onClose: () => void
  onCreateSuccess: ({issue, createMore}: OnCreateProps) => void
  onCreateBulkSuccess: ({parentIssue, createdIssues}: OnCreateBulkProps) => void
}

export function CreateIssueButton({
  issueTemplate,
  issueNode,
  isBulkCreate,
  onClose,
  onCreateSuccess,
  onCreateBulkSuccess,
}: CreateIssueButtonProps) {
  const [dialogOpen, setDialogOpen] = React.useState(false)
  const buttonRef = React.useRef<HTMLButtonElement>(null)

  const {repository: formRepository} = useIssueCreateDataContext()
  const templateRequired = !issueTemplate && !formRepository?.isBlankIssuesEnabled

  const issueFormRef = useRef<IssueFormRef>(null)
  const {labels, assignees, projects, milestone, issueType, clearSessionData} = useIssueCreateDataContext()

  const {sendAnalyticsEvent} = useAnalytics()
  const environment = useRelayEnvironment()

  const onClearSession = useCallback(() => {
    clearSessionData()
    issueFormRef.current?.clearSessionStorage()
  }, [clearSessionData])

  // Clears session storage and closes the content preview window.
  // This mirrors the cleanup logic that we pass into CreateIssueForm.
  const clearOnCreate = useCallback(() => {
    onClearSession()
    onClose?.()
  }, [onClearSession, onClose])

  const handleSubmit = async () => {
    // TODO - Handle validation for issue content: repo, title, body, issue template
    if (issueNode === undefined || formRepository === undefined) {
      return
    }

    // Enforce type here to make sure that we have all required metadata
    const hashInput: IssueMetadata = {
      repositoryId: formRepository.id,
      title: issueNode.item.name,
      body: issueNode.item.body,
      labelIds: labels.length > 0 ? labels.map(label => label.id) : undefined,
      assigneeIds: assignees.length > 0 ? assignees.map(assignee => assignee.id) : undefined,
      milestoneId: milestone?.id,
      issueTypeId: issueTemplate ? issueType?.id : null,
      issueTemplate,
    }
    const response = await createBulkIssuesWithHierarchy(
      issueNode,
      environment,
      hashInput,
      issueTemplate,
      true,
      [],
      projects,
      isBulkCreate,
    )
    if (response instanceof Error) {
      // TODO - handle error case and how we will communicate this to the user
      return
    } else if (response && response.parentIssue) {
      sendAnalyticsEvent('analytics.click', 'ISSUE_CREATE_NEW_ISSUE_BUTTON', {
        issueId: response.parentIssue.id,
        issueNumber: response.parentIssue.number,
        issueNWO: `${response.parentIssue.repository.owner.login}/${response.parentIssue.repository.name}`,
      })
      clearOnCreate()
      if (isBulkCreate) {
        onCreateBulkSuccess(response)
      } else {
        onCreateSuccess({issue: response.parentIssue, createMore: false})
      }
    }
  }

  if (templateRequired) {
    return (
      <>
        <CommandButton
          commandId="github:submit-form"
          variant="primary"
          data-testid="create-issue-dialog-button"
          ref={buttonRef}
          showKeybindingHint
          onClick={e => {
            e.preventDefault()
            setDialogOpen(true)
          }}
        >
          Create
        </CommandButton>
        {dialogOpen && (
          <Dialog
            title="Select a template"
            onClose={() => setDialogOpen(false)}
            footerButtons={[
              {
                buttonType: 'primary',
                content: 'OK',
                onClick: () => setDialogOpen(false),
              },
            ]}
            returnFocusRef={buttonRef}
          >
            This repository requires all issues to have a template. To create this issue, first select the appropriate
            template from the template dropdown.
          </Dialog>
        )}
      </>
    )
  }

  if (copilotFeatureFlags.draftIssueTree) {
    if (issueNode?.parent !== null) {
      // Do not render the button if this is a sub-issue
      return null
    } else {
      return (
        <CommandButton
          commandId="github:submit-form"
          variant="primary"
          data-testid="create-issue-with-bulk-option-button"
          ref={buttonRef}
          showKeybindingHint
          onClick={async e => {
            e.preventDefault()
            await handleSubmit()
          }}
        >
          {isBulkCreate ? 'Create all' : 'Create'}
        </CommandButton>
      )
    }
  }

  return <CreateIssueFooter hideCreateMore className="width-auto" />
}
