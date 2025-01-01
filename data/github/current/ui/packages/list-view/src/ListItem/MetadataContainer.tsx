import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'
import type {ReactElement, ReactNode} from 'react'

import type {StylableProps} from '../types'
import type {ListItemMetadata} from './Metadata'
import styles from './MetadataContainer.module.css'

export type ListItemMetadataContainerProps = StylableProps & {
  children: ReactNode | Array<ReactElement<typeof ListItemMetadata>>
}

export function ListItemMetadataContainer({style, className, children}: ListItemMetadataContainerProps) {
  return (
    <div className={clsx(styles.container, className)} style={style} {...testIdProps('list-view-item-metadata')}>
      {children}
    </div>
  )
}
