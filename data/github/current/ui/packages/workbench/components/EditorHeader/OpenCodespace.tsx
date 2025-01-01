import type {ConnectedCodespaceData} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {CodespacesIcon} from '@primer/octicons-react'
import {ActionList, IconButton} from '@primer/react'
import {memo, useCallback} from 'react'

import {RegionState, useRegionState} from '../../hooks/use-region-state'
import {Region} from '../../types/workbench-types'

export const OpenCodespace = memo(function OpenCodespaceButton({
  className,
  codespaceData,
  variant = 'menu',
}: {
  className?: string
  codespaceData: ConnectedCodespaceData
  variant?: 'menu' | 'icon'
}) {
  const editorState = useRegionState(Region.EDITOR)
  const readOnly = editorState === RegionState.READ_ONLY
  const codespaceName = codespaceData?.codespaceInfo?.environment_data?.friendlyName

  const onCodespaceOpenClick = useCallback(() => {
    if (codespaceName) {
      window.open(`https://${codespaceName}.github.dev`, '_blank')
    }
  }, [codespaceName])

  return variant === 'menu' ? (
    <ActionList.Item aria-label="Open codespace" onSelect={onCodespaceOpenClick} className={className}>
      <ActionList.LeadingVisual>
        <CodespacesIcon />
      </ActionList.LeadingVisual>
      Open codespace
    </ActionList.Item>
  ) : (
    <IconButton
      aria-label="Open codespace"
      className={className}
      icon={CodespacesIcon}
      onClick={onCodespaceOpenClick}
      disabled={readOnly || !codespaceName}
    />
  )
})
