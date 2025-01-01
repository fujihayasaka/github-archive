import type {Icon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'

import styles from './PanelBlankslate.module.css'

interface EmptyPanelStateProps {
  icon: Icon
  title: string
  description?: string
  primaryAction?: string
  primaryActionOnClick?: () => void
  secondaryAction?: string
  actionDisabled?: boolean
}

export function PanelBlankslate({
  icon: Icon,
  title,
  description,
  primaryAction,
  primaryActionOnClick,
  secondaryAction,
  actionDisabled = false,
}: EmptyPanelStateProps) {
  return (
    <div className={styles.container}>
      <Blankslate>
        <Blankslate.Visual>
          <Icon size={32} />
        </Blankslate.Visual>
        <Blankslate.Heading>{title}</Blankslate.Heading>
        {description && (
          <Blankslate.Description className="text-center text-wrap-balance mb-5 mt-3">
            {description}
          </Blankslate.Description>
        )}
        {primaryActionOnClick ? (
          <Button variant="primary" onClick={primaryActionOnClick} disabled={actionDisabled}>
            {primaryAction}
          </Button>
        ) : (
          <>{primaryAction && <Blankslate.PrimaryAction href="#">{primaryAction}</Blankslate.PrimaryAction>}</>
        )}
        {secondaryAction && <Blankslate.SecondaryAction href="#">{secondaryAction}</Blankslate.SecondaryAction>}
      </Blankslate>
    </div>
  )
}
