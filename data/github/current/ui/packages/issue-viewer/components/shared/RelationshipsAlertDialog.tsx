import {useCallback, type PropsWithChildren} from 'react'

import {Dialog, type DialogButtonProps, type DialogHeaderProps, type DialogProps} from '@primer/react/experimental'
import {Header} from '@primer/react'

import styles from './RelationshipsAlertDialog.module.css'

const SingleConfirmBody = ({children}: PropsWithChildren<DialogProps>) => <div className={styles.body}>{children}</div>

const SingleConfirmFooter: React.FC<DialogProps> = ({footerButtons}) => (
  <div className={styles.footer}>
    <Dialog.Buttons buttons={footerButtons ?? []} />
  </div>
)

export const SingleConfirmHeader: React.FC<DialogHeaderProps> = ({title, onClose, dialogLabelId}) => (
  <Header className={styles.header}>
    <Header.Item className={styles.headerItem} id={dialogLabelId}>
      {title}
    </Header.Item>
    <Dialog.CloseButton onClose={useCallback(() => onClose('close-button'), [onClose])} />
  </Header>
)

export interface RelationshipsAlertDialogProps {
  title: string
  children?: React.ReactNode
  width?: DialogProps['width']
  onClose: (gesture: 'confirm' | 'close-button' | 'escape') => void
}

export function RelationshipsAlertDialog({
  title,
  children,
  onClose,
  width = 'medium',
  ...rest
}: RelationshipsAlertDialogProps) {
  const confirmButton: DialogButtonProps = {
    buttonType: 'primary',
    content: 'OK',
    onClick: useCallback(() => onClose('confirm'), [onClose]),
  }

  return (
    <Dialog
      title={title}
      role="alertdialog"
      width={width}
      onClose={onClose}
      footerButtons={[confirmButton]}
      renderBody={SingleConfirmBody}
      renderFooter={SingleConfirmFooter}
      renderHeader={SingleConfirmHeader}
      {...rest}
    >
      {children}
    </Dialog>
  )
}
