// needs to be a separate file from Toolbar to avoid circular imports between Toolbar <-> SavedReplies

import {IconButton, type IconButtonProps} from '@primer/react'
import {forwardRef, useContext} from 'react'

import {MarkdownEditorContext} from './MarkdownEditorContext'
import styles from './ToolbarButton.module.css'

export const ToolbarButton = forwardRef<HTMLButtonElement, IconButtonProps>((props, ref) => {
  const {disabled, condensed} = useContext(MarkdownEditorContext)

  return (
    <IconButton
      ref={ref}
      size={condensed ? 'small' : 'medium'}
      variant="invisible"
      disabled={disabled}
      // Prevent focus leaving input:
      onMouseDown={(e: React.MouseEvent) => e.preventDefault()}
      {...props}
      className={styles.iconButton}
    />
  )
})
ToolbarButton.displayName = 'MarkdownEditor.ToolbarButton'
