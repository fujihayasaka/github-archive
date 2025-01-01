import {CodespaceStatusIndicator} from '@github-ui/shared-workspace-components/CodespaceStatusIndicator'
import {AlertFillIcon, ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {IconButton, Link} from '@primer/react'
import type React from 'react'
import {useEffect, useState} from 'react'

import type {ConnectedCodespaceData} from '../utilities/workspace-editor-types'

interface ITerminalHeaderProps {
  collapseButtonRef: React.RefObject<HTMLButtonElement>
  onDetailsClick: () => void
  isRecoveryContainer?: boolean
  codespaceData: ConnectedCodespaceData
  onTerminalClick: () => void
  onTerminalVisibilityChange: () => void
  isCollapsed: boolean
}

export function TerminalHeader({
  collapseButtonRef,
  onDetailsClick,
  isRecoveryContainer,
  codespaceData,
  onTerminalClick,
  onTerminalVisibilityChange,
  isCollapsed,
}: ITerminalHeaderProps): JSX.Element {
  const [terminalRequested, setTerminalRequested] = useState(false)

  const codespaceDataProps = {
    hasCodespaceInfo: !!codespaceData.codespaceInfo,
    codespaceState: codespaceData?.codespaceState,
    codespaceFriendlyName: codespaceData?.codespaceInfo?.environment_data.friendlyName,
    codespaceSkuDisplayName: codespaceData?.codespaceInfo?.environment_data.skuDisplayName,
    codespacePermissionAccepted: !!codespaceData?.permissionsStatus?.accepted,
    codespaceAllowUrl: codespaceData?.permissionsStatus?.allowPermissionsUrl,
    isCodespaceRecoveryContainer: codespaceData.isRecoveryContainer,
    pollForCodespacePermissionsAccepted: codespaceData.pollForPermissionsAccepted,
    recreateCodespace: codespaceData.recreateCodespace,
    onDetailsClick,
  }

  useEffect(() => {
    if (terminalRequested && codespaceData.codespaceInfo) {
      onTerminalClick()
      setTerminalRequested(false)
    }
  }, [codespaceData.codespaceInfo, onTerminalClick, terminalRequested])

  const collapseButtonComponent = (
    <IconButton
      icon={isCollapsed ? ChevronUpIcon : ChevronDownIcon}
      variant="invisible"
      aria-label={isCollapsed ? 'Expand' : 'Collapse'}
      onClick={onTerminalVisibilityChange}
      ref={collapseButtonRef}
    />
  )

  return (
    <div className="position-absolute d-flex flex-items-center" style={{top: '8px', right: '8px'}}>
      {isRecoveryContainer && (
        <div className="d-flex gap-1 mx-1 flex-items-center text-small no-wrap color-fg-muted">
          <AlertFillIcon className="w-16 h-16 color-fg-attention" />
          <span>Using recovery image.</span>
          <Link className="cursor-pointer color-fg-muted" onClick={onDetailsClick} inline>
            Details
          </Link>
        </div>
      )}
      <CodespaceStatusIndicator {...codespaceDataProps} />
      {collapseButtonComponent}
    </div>
  )
}
