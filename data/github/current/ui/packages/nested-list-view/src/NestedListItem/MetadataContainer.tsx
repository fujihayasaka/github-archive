import {testIdProps} from '@github-ui/test-id-props'
import {type BetterSystemStyleObject, Box} from '@primer/react'
import {clsx} from 'clsx'
import {type ReactElement, type ReactNode, useRef} from 'react'

import {useNestedListItemControlsDialog} from './context/ControlsDialogContext'
import {useSuppressActions} from './hooks/use-suppress-actions'
import type {NestedListItemMetadata} from './Metadata'
import styles from './MetadataContainer.module.css'

export interface MetadataContainerProps {
  sx?: BetterSystemStyleObject
  children: ReactNode | Array<ReactElement<typeof NestedListItemMetadata>>
  className?: string
}

export function NestedListItemMetadataContainer({sx, children, className}: MetadataContainerProps) {
  const metadataContainerRef = useRef<HTMLDivElement>(null)
  const {controlsDialogOpen} = useNestedListItemControlsDialog()

  useSuppressActions(metadataContainerRef)

  return (
    <Box
      ref={metadataContainerRef}
      aria-hidden={!controlsDialogOpen} // only reveal these controls to screen readers when the management dialog is open
      sx={sx}
      {...testIdProps('nested-list-view-item-metadata')}
      className={clsx(styles.metadataContainer, className)}
    >
      {children}
    </Box>
  )
}
