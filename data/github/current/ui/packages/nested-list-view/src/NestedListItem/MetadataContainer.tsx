import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import {type ReactElement, type ReactNode, useRef} from 'react'

import {useNestedListItemControlsDialog} from './context/ControlsDialogContext'
import {useSuppressActions} from './hooks/use-suppress-actions'
import type {NestedListItemMetadata} from './Metadata'
import styles from './MetadataContainer.module.css'

export interface MetadataContainerProps {
  children: ReactNode | Array<ReactElement<typeof NestedListItemMetadata>>
  className?: string
}

export function NestedListItemMetadataContainer({children, className}: MetadataContainerProps) {
  const metadataContainerRef = useRef<HTMLDivElement>(null)
  const {controlsDialogOpen} = useNestedListItemControlsDialog()

  useSuppressActions(metadataContainerRef)

  return (
    <div
      ref={metadataContainerRef}
      aria-hidden={!controlsDialogOpen} // only reveal these controls to screen readers when the management dialog is open
      {...testIdProps('nested-list-view-item-metadata')}
      className={clsx(styles.metadataContainer, className)}
    >
      {children}
    </div>
  )
}
