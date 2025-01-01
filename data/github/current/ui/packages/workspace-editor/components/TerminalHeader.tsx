import {AlertFillIcon, TrashIcon, XIcon} from '@primer/octicons-react'
import {IconButton, Link} from '@primer/react'
import type React from 'react'
import {useCallback} from 'react'

import {useTerminalContext} from '../contexts/TerminalContext'

interface ITerminalHeaderProps {
  closeButtonRef: React.RefObject<HTMLButtonElement>
  onTerminalVisibilityChange: (visibility: 'visible' | 'hidden') => void
  onDetailsClick: () => void
  isRecoveryContainer?: boolean
}

export function TerminalHeader({
  closeButtonRef,
  onTerminalVisibilityChange,
  onDetailsClick,
  isRecoveryContainer,
}: ITerminalHeaderProps): JSX.Element {
  const {
    dispatch,
    state: {history},
  } = useTerminalContext()
  const clearAll = useCallback(() => {
    dispatch({type: 'CLEAR_ALL'})
    closeButtonRef.current?.focus()
  }, [closeButtonRef, dispatch])
  return (
    <div className="position-absolute d-flex flex-items-center" style={{top: '8px', right: '8px'}}>
      {Object.keys(history).length > 0 && (
        <IconButton aria-label="Clear all" icon={TrashIcon} variant="invisible" onClick={clearAll} />
      )}
      {isRecoveryContainer && (
        <div className="d-flex gap-1 mx-1 flex-items-center text-small no-wrap color-fg-muted">
          <AlertFillIcon className="w-16 h-16 color-fg-attention" />
          <span>Using recovery image.</span>
          <Link className="cursor-pointer color-fg-muted" onClick={onDetailsClick} inline>
            Details
          </Link>
        </div>
      )}
      <IconButton
        ref={closeButtonRef}
        icon={XIcon}
        variant="invisible"
        aria-label="Close"
        onClick={() => onTerminalVisibilityChange('hidden')}
      />
    </div>
  )
}
