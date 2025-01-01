import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ButtonGroup, IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {useRef, useState} from 'react'
import {DiffLinesAskCopilotButton} from '../shared/DiffLinesAskCopilotButton'
import styles from './DiffLinesMenu.module.css'
import {DiffLinesExplainMenuItem} from '../shared/DiffLinesExplainMenuItem'
import {DiffLinesAttachMenuItem} from '../shared/DiffLinesAttachMenuItem'

export interface DiffLinesMenuProps {
  fileDiffReference: FileDiffReference
  style?: React.CSSProperties
  onOpenChange?: (open: boolean) => void
}

export const DiffLinesMenu = ({fileDiffReference, onOpenChange}: DiffLinesMenuProps) => {
  const [open, _setOpen] = useState(false)
  const setOpen = (newOpen: boolean) => {
    _setOpen(newOpen)
    onOpenChange?.(newOpen)
  }

  const buttonRef = useRef<HTMLButtonElement>(null)

  const closeMenu = () => setOpen(false)

  return (
    <ButtonGroup className={styles['diff-button-container']}>
      <DiffLinesAskCopilotButton fileDiffReference={fileDiffReference} afterSelect={closeMenu} />
      <ActionMenu open={open} onOpenChange={setOpen} anchorRef={buttonRef}>
        <ActionMenu.Anchor>
          <IconButton
            icon={TriangleDownIcon}
            aria-label="Copilot menu"
            ref={buttonRef}
            onSelect={() => setOpen(true)}
            size="small"
            className={clsx(styles['square'], styles['diff-button'])}
            data-testid="more-copilot-button"
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay align="end">
          <ActionList>
            <DiffLinesExplainMenuItem fileDiffReference={fileDiffReference} afterSelect={closeMenu} />
            <ActionList.Divider />
            <DiffLinesAttachMenuItem fileDiffReference={fileDiffReference} afterSelect={closeMenu} />
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </ButtonGroup>
  )
}
