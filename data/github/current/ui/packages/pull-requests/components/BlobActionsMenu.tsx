import {
  CopilotDiffChatBlobActionsMenuItems,
  type CopilotDiffChatBlobActionsMenuItemsProps,
} from '@github-ui/copilot-code-chat/CopilotDiffChatBlobActionsMenuItems'
import type {RepositoryNWO} from '@github-ui/current-repository'
import {blobPath, deleteBlobPath, editBlobPath} from '@github-ui/paths'
import {EyeIcon, KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'

interface BlobActionsMenuProps {
  oid: string
  path: string
  repo: RepositoryNWO
  branchName?: string
  isViewable?: boolean
  copilotDiffChatProps?: CopilotDiffChatBlobActionsMenuItemsProps
}

export function BlobActionsMenu({
  oid,
  path,
  repo,
  branchName,
  isViewable = true,
  copilotDiffChatProps,
}: BlobActionsMenuProps) {
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <button className="Button Button--iconOnly Button--invisible" aria-label="More options">
          <KebabHorizontalIcon />
        </button>
      </ActionMenu.Anchor>

      <ActionMenu.Overlay>
        <ActionList>
          <ActionList.LinkItem
            href={blobPath({
              repo: repo.name,
              owner: repo.ownerLogin,
              filePath: path,
              commitish: oid,
            })}
            inactiveText={isViewable ? undefined : 'Action unavailable'}
          >
            <ActionList.LeadingVisual>
              <EyeIcon />
            </ActionList.LeadingVisual>
            View file
          </ActionList.LinkItem>
          {branchName && (
            <>
              <ActionList.LinkItem
                href={editBlobPath({
                  repo: repo.name,
                  owner: repo.ownerLogin,
                  filePath: path,
                  commitish: branchName,
                })}
              >
                <ActionList.LeadingVisual>
                  <PencilIcon />
                </ActionList.LeadingVisual>
                Edit file
              </ActionList.LinkItem>
              <ActionList.LinkItem
                variant="danger"
                href={deleteBlobPath({
                  repo: repo.name,
                  owner: repo.ownerLogin,
                  filePath: path,
                  commitish: branchName,
                })}
              >
                <ActionList.LeadingVisual>
                  <TrashIcon />
                </ActionList.LeadingVisual>
                Delete file
              </ActionList.LinkItem>
            </>
          )}
          {copilotDiffChatProps && <CopilotDiffChatBlobActionsMenuItems {...copilotDiffChatProps} />}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
