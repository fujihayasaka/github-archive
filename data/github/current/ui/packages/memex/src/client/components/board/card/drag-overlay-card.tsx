import {noop} from '@github-ui/noop'
import {testIdProps} from '@github-ui/test-id-props'
import {useRef} from 'react'

import type {MemexItemModel} from '../../../models/memex-item-model'
import {CardBaseWithSash} from './card-base-with-sash'
import {CardInternalContent} from './card-internal-content'
import styles from './drag-overlay-card.module.css'

export function DragOverlayCard({item}: {item: MemexItemModel}) {
  return (
    <CardBaseWithSash inert="inert" className={styles.CardBaseWithSash} {...testIdProps('drag-overlay')}>
      <CardInternalContent item={item} contextMenuRef={useRef(null)} removeItem={noop} isDragging />
    </CardBaseWithSash>
  )
}
