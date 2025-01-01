import {useState, useRef, useCallback} from 'react'
import {CopilotIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {CopilotPlanBrainstormDialog} from './CopilotPlanBrainstormDialog'

export interface CopilotPlanBrainstormButtonProps {
  title?: string
  markdown: string
  copilotApiUrl: string
  nameWithOwner?: string
}

export function CopilotPlanBrainstormButton(props: CopilotPlanBrainstormButtonProps) {
  const [isOpen, setIsOpen] = useState(false)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const onDialogClose = useCallback(() => setIsOpen(false), [])
  const onDialogOpen = useCallback(() => setIsOpen(true), [])

  return (
    <>
      <Button leadingVisual={CopilotIcon} size="small" ref={buttonRef} onClick={onDialogOpen}>
        Plan & Brainstorm
      </Button>
      {isOpen && <CopilotPlanBrainstormDialog onClose={onDialogClose} {...props} />}
    </>
  )
}
