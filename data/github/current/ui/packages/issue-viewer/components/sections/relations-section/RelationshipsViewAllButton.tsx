import {useState, useRef, useCallback, type PropsWithChildren} from 'react'
import {ArrowRightIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {RelationshipsListAllModal} from './RelationshipsListAllModal'
import styles from './RelationshipsViewAllButton.module.css'
import {LABELS} from '../../../constants/labels'

export type RelationshipsViewAllButtonProps = PropsWithChildren<{
  dialogTitle: string
  countOpenItems: number
}>

export function RelationshipsViewAllButton({dialogTitle, countOpenItems, children}: RelationshipsViewAllButtonProps) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const linkItemRef = useRef<HTMLLIElement>(null)
  const onDialogClose = useCallback(() => setIsDialogOpen(false), [])

  return (
    <>
      <ActionList.Item onSelect={() => setIsDialogOpen(!isDialogOpen)} ref={linkItemRef}>
        <ActionList.LeadingVisual>
          <div className={styles.RelationshipsViewAllButton_LeadingSpacer} />
        </ActionList.LeadingVisual>

        <span className={styles.RelationshipsViewAllButton_Label}>
          {LABELS.relationViewAll} <ArrowRightIcon />
        </span>
      </ActionList.Item>

      {isDialogOpen && (
        <RelationshipsListAllModal dialogTitle={dialogTitle} countOpenItems={countOpenItems} onClose={onDialogClose}>
          {children}
        </RelationshipsListAllModal>
      )}
    </>
  )
}
