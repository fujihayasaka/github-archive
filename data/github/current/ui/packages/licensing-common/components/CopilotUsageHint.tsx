import {AnchoredOverlay, IconButton, Stack, Text} from '@primer/react'
import {clsx} from 'clsx'
import styles from './CopilotUsageHint.module.css'
import {InfoIcon} from '@primer/octicons-react'
import {useOverlayControls} from '../hooks/use-overlay-controls'

export interface CopilotUsageHintProps {
  title: string
  description?: string
  children?: React.ReactNode
}

export function CopilotUsageHint({title, description, children}: CopilotUsageHintProps) {
  const {close: closeOverlay, isOpen: isOverlayOpen, open: openOverlay} = useOverlayControls()
  const ariaLabel = `Learn more about ${title}`
  return (
    <AnchoredOverlay
      open={isOverlayOpen}
      onOpen={openOverlay}
      onClose={closeOverlay}
      renderAnchor={props => (
        <IconButton
          size="small"
          variant="invisible"
          icon={InfoIcon}
          {...props}
          aria-label={ariaLabel}
          aria-labelledby={undefined}
          data-testid="usage-hint-button"
        />
      )}
      side="outside-top"
      width="medium"
    >
      <Stack
        className={clsx(styles.overlayBoxWrapper)}
        direction="vertical"
        gap="normal"
        justify="center"
        padding="spacious"
      >
        <Text className={clsx(styles.overlayBoxTitle)} size="medium" weight="semibold" data-testid="usage-hint-title">
          {title}
        </Text>
        <Text className={clsx(styles.overlayBoxDescription)} size="medium" data-testid="usage-hint-description">
          {description}
        </Text>
        {children}
      </Stack>
    </AnchoredOverlay>
  )
}
