import {CopilotIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import type {ComponentProps} from 'react'
import {useRef} from 'react'
import styles from './AskCopilotButton.module.css'

export interface AskCopilotButtonProps
  extends Omit<ComponentProps<typeof IconButton>, 'icon' | 'aria-label' | 'aria-labelledby'> {
  referenceType: string
}

export function AskCopilotButton({children, referenceType, ...props}: AskCopilotButtonProps) {
  const contentRef = useRef<HTMLButtonElement>(null)

  return (
    <>
      <IconButton
        className={clsx(styles['square'], !!children && styles['muted'])}
        ref={contentRef}
        icon={CopilotIcon}
        size="small"
        aria-label={`Ask Copilot about this ${referenceType}`}
        data-testid="copilot-ask-menu"
        {...props}
      />
    </>
  )
}
