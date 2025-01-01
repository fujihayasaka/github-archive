import {AlertFillIcon, CodespacesIcon, PlusIcon, QuestionIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Spinner} from '@primer/react'
import {memo, useMemo, useState} from 'react'

import type {ConnectedCodespaceData} from '../../utilities/workspace-editor-types'

export type ICodespaceDropdownProps = {
  codespaceData: ConnectedCodespaceData
  onDetailsClick: () => void
}

export const CodespaceDropdown = memo(function CodespaceDropdown({
  codespaceData,
  onDetailsClick,
}: ICodespaceDropdownProps) {
  const [fetchingPermissionsStatus, setFetchingPermissionsStatus] = useState<boolean>(false)

  const formattedFriendlyName = useMemo(() => {
    if (!codespaceData.codespaceInfo?.environment_data?.friendlyName) {
      return ''
    }

    const parts = codespaceData.codespaceInfo.environment_data.friendlyName.split('-')
    parts.pop()
    return parts.join(' ')
  }, [codespaceData])

  const showAlert = useMemo(() => {
    const missingPermissions =
      !codespaceData.permissionsStatus?.accepted && codespaceData.permissionsStatus?.allowPermissionsUrl
    if (codespaceData.isRecoveryContainer || missingPermissions) {
      return true
    }

    return false
  }, [codespaceData.isRecoveryContainer, codespaceData.permissionsStatus])

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <div className="position-relative">
          <IconButton icon={CodespacesIcon} aria-label="Codespace details" variant="invisible" />
          {showAlert && (
            <AlertFillIcon
              className="position-absolute right-0 bottom-0 mr-1 mb-1 color-fg-attention pointer-none"
              size={12}
            />
          )}
        </div>
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="medium" align="end">
        <ActionList>
          <div className="px-3 py-1 d-flex flex-column">
            <span className="text-bold">
              Codespace &quot;{formattedFriendlyName}
              &quot;
            </span>
            <span className="text-small color-fg-muted">
              {codespaceData.codespaceInfo?.environment_data.skuDisplayName}
            </span>
          </div>
          <ActionList.Divider />
          <ActionList.Group>
            {codespaceData.isRecoveryContainer && (
              <ActionList.Item onSelect={onDetailsClick}>
                <ActionList.LeadingVisual>
                  <AlertFillIcon className="color-fg-attention" />
                </ActionList.LeadingVisual>
                <span className="color-fg-attention">Problem starting codespace</span>
                <ActionList.Description variant="block">View details</ActionList.Description>
              </ActionList.Item>
            )}
            {fetchingPermissionsStatus && (
              <ActionList.Item disabled>
                <ActionList.LeadingVisual>
                  <Spinner size="small" />
                </ActionList.LeadingVisual>
                Waiting for permissions to be accepted
              </ActionList.Item>
            )}
            {!fetchingPermissionsStatus && showAlert && (
              <ActionList.LinkItem
                href={codespaceData.permissionsStatus?.allowPermissionsUrl}
                target="_blank"
                onClick={async () => {
                  setFetchingPermissionsStatus(true)
                  try {
                    await codespaceData.pollForPermissionsAccepted()
                  } finally {
                    setFetchingPermissionsStatus(false)
                  }
                }}
              >
                <ActionList.LeadingVisual>
                  <AlertFillIcon className="color-fg-attention" />
                </ActionList.LeadingVisual>
                <span className="color-fg-attention">Additional permissions required</span>
                <ActionList.Description variant="block">Review permissions</ActionList.Description>
              </ActionList.LinkItem>
            )}
            <ActionList.Item onSelect={() => codespaceData.recreateCodespace()}>
              <ActionList.LeadingVisual>
                <PlusIcon />
              </ActionList.LeadingVisual>
              Create a new codespace
            </ActionList.Item>
            <ActionList.LinkItem href="https://docs.github.com/en/codespaces/overview" target="_blank">
              <ActionList.LeadingVisual>
                <QuestionIcon />
              </ActionList.LeadingVisual>
              What is a codespace?
            </ActionList.LinkItem>
          </ActionList.Group>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
})
