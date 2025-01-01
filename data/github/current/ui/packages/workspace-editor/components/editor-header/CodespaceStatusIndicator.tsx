import {AlertFillIcon} from '@primer/octicons-react'
import {Link, Spinner} from '@primer/react'
import {memo} from 'react'

import type {ConnectedCodespaceData} from '../../utilities/workspace-editor-types'
import {CodespaceDropdown} from './CodespaceDropdown'

export type ICodespaceStatusIndicator = {
  codespaceData: ConnectedCodespaceData
  onDetailsClick: () => void
}

export const CodespaceStatusIndicator = memo(function CodespaceStatusIndicator({
  codespaceData,
  onDetailsClick,
}: ICodespaceStatusIndicator) {
  let codespaceStatusComponent = <></>
  if (['none', 'creating', 'starting'].includes(codespaceData.codespaceState)) {
    codespaceStatusComponent = (
      <div className="d-flex gap-1 mx-1 flex-items-center text-small no-wrap color-fg-muted">
        <Spinner size="small" />
        <span>Starting codespace...</span>
      </div>
    )
  } else if (codespaceData.codespaceState === 'failed') {
    codespaceStatusComponent = (
      <div className="d-flex gap-1 mx-1 flex-items-center text-small no-wrap color-fg-muted">
        <AlertFillIcon className="w-16 h-16 color-fg-attention" />
        <span>Failed to start codespace.</span>
        <Link className="cursor-pointer color-fg-muted" onClick={onDetailsClick} inline>
          Details
        </Link>
      </div>
    )
  } else if (codespaceData.codespaceState === 'ready') {
    codespaceStatusComponent = <CodespaceDropdown codespaceData={codespaceData} onDetailsClick={onDetailsClick} />
  }

  return codespaceStatusComponent
})
