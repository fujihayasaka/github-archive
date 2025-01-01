import {AlertFillIcon} from '@primer/octicons-react'
import {Link, Spinner} from '@primer/react'
import {memo} from 'react'

import type {SharedCodespaceProps, TCodespaceState} from '../utilities/workspace-editor-types'
import {CodespaceDropdown} from './CodespaceDropdown'

export type ICodespaceStatusIndicator = SharedCodespaceProps & {
  codespaceState: TCodespaceState
  onDetailsClick: () => void
  codespaceUrl?: string
}

export const CodespaceStatusIndicator = memo(function CodespaceStatusIndicator({
  codespaceState,
  codespaceFriendlyName,
  codespaceSkuDisplayName,
  codespacePermissionAccepted,
  codespaceAllowUrl,
  isCodespaceRecoveryContainer,
  pollForCodespacePermissionsAccepted,
  recreateCodespace,
  onDetailsClick,
  codespaceUrl = '',
}: ICodespaceStatusIndicator) {
  let codespaceStatusComponent = <></>
  if (['none', 'creating', 'starting'].includes(codespaceState)) {
    codespaceStatusComponent = (
      <div className="d-flex gap-1 mx-1 flex-items-center text-small no-wrap color-fg-muted">
        <Spinner size="small" />
        <span>Starting codespace...</span>
      </div>
    )
  } else if (codespaceState === 'failed') {
    codespaceStatusComponent = (
      <div className="d-flex gap-1 mx-1 flex-items-center text-small no-wrap color-fg-muted">
        <AlertFillIcon className="w-16 h-16 color-fg-attention" />
        <span>Failed to start codespace.</span>
        <Link className="cursor-pointer color-fg-muted" onClick={onDetailsClick} inline>
          Details
        </Link>
      </div>
    )
  } else if (codespaceState === 'ready') {
    codespaceStatusComponent = (
      <CodespaceDropdown
        codespaceFriendlyName={codespaceFriendlyName}
        codespaceSkuDisplayName={codespaceSkuDisplayName}
        codespacePermissionAccepted={codespacePermissionAccepted}
        codespaceAllowUrl={codespaceAllowUrl}
        isCodespaceRecoveryContainer={isCodespaceRecoveryContainer}
        pollForCodespacePermissionsAccepted={pollForCodespacePermissionsAccepted}
        recreateCodespace={recreateCodespace}
        onDetailsClick={onDetailsClick}
        codespaceUrl={codespaceUrl}
      />
    )
  }

  return codespaceStatusComponent
})
