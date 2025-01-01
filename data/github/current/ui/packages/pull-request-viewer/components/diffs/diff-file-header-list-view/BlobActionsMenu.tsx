import {EyeIcon, KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import {diffBlobBranchPath, diffBlobPath, workspaceEditorPath} from '../../../helpers/diff-link-helpers'
import {usePullRequestAnalytics} from '../../../hooks/use-pull-request-analytics'
import usePullRequestPageAppPayload from '../../../hooks/use-pull-request-page-app-payload'
import type {BlobActionsMenu_diffEntry$key} from './__generated__/BlobActionsMenu_diffEntry.graphql'
import type {BlobActionsMenu_pullRequest$key} from './__generated__/BlobActionsMenu_pullRequest.graphql'

interface BlobActionsMenuProps {
  diffEntry: BlobActionsMenu_diffEntry$key
  pullRequest: BlobActionsMenu_pullRequest$key
}

export default function BlobActionsMenu({diffEntry, pullRequest}: BlobActionsMenuProps) {
  const pullRequestData = useFragment(
    graphql`
      fragment BlobActionsMenu_pullRequest on PullRequest {
        number
        headRefName
        headRepository {
          nameWithOwner
        }
        baseRepository {
          nameWithOwner
        }
        viewerCanEditFiles
      }
    `,
    pullRequest,
  )

  const diffEntryData = useFragment(
    graphql`
      fragment BlobActionsMenu_diffEntry on PullRequestDiffEntry {
        path
        oid
        status
        isSubmodule
        isBinary
        isLfsPointer
      }
    `,
    diffEntry,
  )

  const {isBinary, isLfsPointer, isSubmodule, status, oid, path} = diffEntryData
  const {number: pullRequestNumber, viewerCanEditFiles, headRepository, headRefName, baseRepository} = pullRequestData

  const editableInOnlineEditor = !isBinary && !isLfsPointer
  const isViewable = !isSubmodule
  const {workspaceEditorEnabled} = usePullRequestPageAppPayload()

  const diffEntryLinkData = {oid, status, path}
  const pullRequestLinkData = {
    headRefName,
    headRepositoryNameWithOwner: headRepository?.nameWithOwner,
    baseRepositoryNameWithOwner: baseRepository?.nameWithOwner,
    number: Number(pullRequestNumber),
  }

  const viewLink = `${diffBlobPath(diffEntryLinkData, pullRequestLinkData)}`
  const editLink = workspaceEditorEnabled
    ? workspaceEditorPath(diffEntryLinkData, pullRequestLinkData)
    : diffBlobBranchPath('edit', diffEntryLinkData, pullRequestLinkData)
  const deleteLink = `${diffBlobBranchPath('delete', diffEntryLinkData, pullRequestLinkData)}`

  const {sendPullRequestAnalyticsEvent} = usePullRequestAnalytics()

  function renderEditListItem() {
    if (isSubmodule) return null
    if (viewerCanEditFiles && editableInOnlineEditor) {
      return (
        <ActionList.LinkItem
          aria-label="Change this file using the online editor."
          href={editLink}
          onClick={() => sendPullRequestAnalyticsEvent('file_entry.edit_file', 'BLOB_ACTIONS_MENU_ITEM')}
        >
          <ActionList.LeadingVisual>
            <PencilIcon />
          </ActionList.LeadingVisual>
          Edit file
        </ActionList.LinkItem>
      )
    }

    const label = !editableInOnlineEditor
      ? 'Online editor is disabled for binary and Git LFS files.'
      : 'You must be signed in and have push access to make changes.'

    return (
      <ActionList.Item disabled aria-label={label}>
        <ActionList.LeadingVisual>
          <PencilIcon />
        </ActionList.LeadingVisual>
        Edit file
      </ActionList.Item>
    )
  }

  function renderDeleteListItem() {
    if (isSubmodule) return null
    if (viewerCanEditFiles) {
      return (
        <ActionList.LinkItem
          aria-label="Delete this file"
          href={deleteLink}
          sx={{color: 'danger.fg', '&:hover': {color: 'danger.fg'}}}
          onClick={() => sendPullRequestAnalyticsEvent('file_entry.delete_file', 'BLOB_ACTIONS_MENU_ITEM')}
        >
          <ActionList.LeadingVisual sx={{color: 'danger.fg'}}>
            <TrashIcon />
          </ActionList.LeadingVisual>
          Delete file
        </ActionList.LinkItem>
      )
    } else {
      return (
        <ActionList.Item disabled aria-label="You must be signed in and have push access to delete this file.">
          <ActionList.LeadingVisual>
            <TrashIcon />
          </ActionList.LeadingVisual>
          Delete file
        </ActionList.Item>
      )
    }
  }

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton unsafeDisableTooltip aria-label="More options" icon={KebabHorizontalIcon} variant="invisible" />
      </ActionMenu.Anchor>

      <ActionMenu.Overlay>
        <ActionList>
          {/* TODO: <ActionList.Item disabled={true}>
            <ActionList.LeadingVisual>
              <CheckIcon />
            </ActionList.LeadingVisual>
            Show annotations (TODO)
          </ActionList.Item>
          <ActionList.Divider /> */}
          {isViewable && (
            <ActionList.LinkItem
              href={viewLink}
              onClick={() => sendPullRequestAnalyticsEvent('file_entry.view_file', 'BLOB_ACTIONS_MENU_ITEM')}
            >
              <ActionList.LeadingVisual>
                <EyeIcon />
              </ActionList.LeadingVisual>
              View file
            </ActionList.LinkItem>
          )}
          {renderEditListItem()}
          {renderDeleteListItem()}
          {/* TODO: work in a non-relay version of copilot diff chat from ui/packages/copilot-code-chat */}
          {/* TODO: <ActionList.Divider />
          <ActionList.Item disabled={true}>
            <ActionList.LeadingVisual>
              <DeviceDesktopIcon />
            </ActionList.LeadingVisual>
            Open in desktop (TODO)
          </ActionList.Item> */}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
