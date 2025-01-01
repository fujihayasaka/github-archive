import {PaperclipIcon} from '@primer/octicons-react'
import type React from 'react'
import {forwardRef, memo, useContext} from 'react'

import type {ButtonProps} from '@primer/react'
import {Button} from '@primer/react'
import {useSlots} from '@primer/react/experimental'
import {MarkdownEditorContext} from './MarkdownEditorContext'

import styles from './Footer.module.css'

export const CoreFooter = ({children}: {children: React.ReactNode}) => {
  const [slots, childrenWithoutSlots] = useSlots(children, {
    footerButtons: FooterButton,
  })

  return (
    <footer className={styles.footer}>
      <div className={styles.footerWrapper}>
        {slots.footerButtons && <div className={styles.footerButtonWrapper}>{slots.footerButtons}</div>}
        <DefaultFooterButtons />
      </div>
      <div className={styles.childrenStyling}>{childrenWithoutSlots}</div>
    </footer>
  )
}

export const Footer = ({children}: {children?: React.ReactNode}) => <CoreFooter>{children}</CoreFooter>
Footer.displayName = 'MarkdownEditor.Footer'

export const FooterButton = forwardRef<HTMLButtonElement, ButtonProps>((props, ref) => {
  const {disabled} = useContext(MarkdownEditorContext)
  return <Button ref={ref} size="small" disabled={disabled} {...props} />
})
FooterButton.displayName = 'MarkdownEditor.FooterButton'

const DefaultFooterButtons = memo(() => {
  const {uploadButtonProps, fileDraggedOver} = useContext(MarkdownEditorContext)

  return uploadButtonProps ? <FileUploadButton fileDraggedOver={fileDraggedOver} {...uploadButtonProps} /> : null
})
DefaultFooterButtons.displayName = 'MarkdownEditor.DefaultFooterButtons'

const FileUploadButton = memo(({fileDraggedOver, ...props}: Partial<ButtonProps> & {fileDraggedOver: boolean}) => {
  const {condensed, disabled, fileUploadProgress} = useContext(MarkdownEditorContext)
  const currentFileUpload = fileUploadProgress?.[0]
  const totalFileUploads = fileUploadProgress?.[1]
  const isUploading = Boolean(totalFileUploads)
  const fileUploadProgressString =
    totalFileUploads === 1
      ? 'Uploading your file...'
      : `Uploading your files... (${currentFileUpload}/${totalFileUploads})`

  return (
    <Button
      variant="invisible"
      loadingAnnouncement={isUploading ? fileUploadProgressString : undefined}
      leadingVisual={PaperclipIcon}
      loading={isUploading}
      size="small"
      className={styles.footerButton}
      onMouseDown={(e: React.MouseEvent) => {
        // Prevent pulling focus from the textarea
        e.preventDefault()
      }}
      disabled={disabled}
      {...props}
    >
      {condensed ? 'Add files' : fileDraggedOver ? 'Drop to add files' : 'Paste, drop, or click to add files'}
    </Button>
  )
})
FileUploadButton.displayName = 'MarkdownEditor.FileUploadButton'
