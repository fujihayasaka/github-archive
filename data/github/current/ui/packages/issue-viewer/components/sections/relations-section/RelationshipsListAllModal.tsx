import type {PropsWithChildren} from 'react'
import {CounterLabel, Dialog, type DialogProps} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {PreviewCardOutlet} from '@github-ui/preview-card'
import styles from './RelationshipsListAllModal.module.css'
import {testIdProps} from '@github-ui/test-id-props'
import {LABELS} from '../../../constants/labels'

export const TEST_ID_COUNTER = '__test-relationships-list-all-modal-counter'

export type RelationshipsListAllModalProps = PropsWithChildren<{
  dialogTitle: string
  countOpenItems?: number
  totalItems?: number
  onClose: DialogProps['onClose']
  returnFocusRef?: DialogProps['returnFocusRef']
}>
export function RelationshipsListAllModal({
  dialogTitle,
  countOpenItems = -1,
  onClose,
  returnFocusRef,
  children,
}: RelationshipsListAllModalProps) {
  const titleComponent = <RelationshipListAllModalTitle title={dialogTitle} count={countOpenItems} />

  const errorComponent = (
    <Banner variant="critical">
      <Banner.Title>{LABELS.relationListAllError}</Banner.Title>
    </Banner>
  )

  return (
    <Dialog title={titleComponent} onClose={onClose} returnFocusRef={returnFocusRef} width="xlarge" height="large">
      <ErrorBoundary fallback={errorComponent}>
        <div className={`${styles.RelationshipsListAllModal_HovercardWrapper}`}>
          <PreviewCardOutlet />
        </div>
        {children}
      </ErrorBoundary>
    </Dialog>
  )
}

type RelationshipListAllModalTitleProps = {
  title: string
  count: number
}
function RelationshipListAllModalTitle({title, count}: RelationshipListAllModalTitleProps) {
  return (
    <span>
      {title}
      {count >= 0 && (
        <CounterLabel className={styles.RelationshipsListAllModal_TitleCounter} {...testIdProps(TEST_ID_COUNTER)}>
          {count}
        </CounterLabel>
      )}
    </span>
  )
}
