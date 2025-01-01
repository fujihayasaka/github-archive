import {AlertFillIcon, CodespacesIcon, PlusIcon, QuestionIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Spinner} from '@primer/react'
import {memo, useCallback, useMemo, useRef, useState} from 'react'
import type {SharedCodespaceProps} from '../utilities/workspace-editor-types'

export type ICodespaceDropdownProps = SharedCodespaceProps & {
  onDetailsClick: () => void
}

export const CodespaceDropdown = memo(function CodespaceDropdown({
  codespaceFriendlyName,
  codespaceSkuDisplayName,
  codespacePermissionAccepted,
  codespaceAllowUrl,
  isCodespaceRecoveryContainer,
  pollForCodespacePermissionsAccepted,
  recreateCodespace,
  onDetailsClick,
}: ICodespaceDropdownProps) {
  const anchorRef = useRef<HTMLButtonElement>(null)
  const [open, setOpen] = useState(false)

  const [fetchingPermissionsStatus, setFetchingPermissionsStatus] = useState<boolean>(false)

  const formattedFriendlyName = useMemo(() => {
    if (!codespaceFriendlyName) {
      return ''
    }

    const parts = codespaceFriendlyName.split('-')
    parts.pop()
    return parts.join(' ')
  }, [codespaceFriendlyName])

  const showAlert = useMemo(() => {
    const missingPermissions = !codespacePermissionAccepted && codespaceAllowUrl
    if (isCodespaceRecoveryContainer || missingPermissions) {
      return true
    }

    return false
  }, [codespaceAllowUrl, codespacePermissionAccepted, isCodespaceRecoveryContainer])

  const toggleOpen = useCallback(() => setOpen(!open), [open, setOpen])

  return (
    <>
      <div className="position-relative">
        <IconButton
          icon={CodespacesIcon}
          aria-label="Codespace details"
          variant="invisible"
          ref={anchorRef}
          onClick={toggleOpen}
        />
        {showAlert && (
          <AlertFillIcon
            className="position-absolute right-0 bottom-0 mr-1 mb-1 color-fg-attention pointer-none"
            size={12}
          />
        )}
      </div>
      <ActionMenu anchorRef={anchorRef} open={open} onOpenChange={setOpen}>
        <ActionMenu.Overlay width="medium" align="end">
          <ActionList>
            <div className="px-3 py-1 d-flex flex-column">
              <span className="text-bold">
                Codespace &quot;{formattedFriendlyName}
                &quot;
              </span>
              <span className="text-small color-fg-muted">{codespaceSkuDisplayName}</span>
            </div>
            <ActionList.Divider />
            <ActionList.Group>
              {isCodespaceRecoveryContainer && (
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
                  href={codespaceAllowUrl}
                  target="_blank"
                  onClick={async () => {
                    setFetchingPermissionsStatus(true)
                    try {
                      await pollForCodespacePermissionsAccepted()
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
              <ActionList.Item onSelect={() => recreateCodespace()}>
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
    </>
  )
})
