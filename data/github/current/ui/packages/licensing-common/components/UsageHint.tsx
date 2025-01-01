import {AnchoredOverlay, IconButton, Link, Stack, Text} from '@primer/react'
import {clsx} from 'clsx'
import styles from './UsageHint.module.css'
import {InfoIcon} from '@primer/octicons-react'
import {useOverlayControls} from '../hooks/use-overlay-controls'

export interface UsageHintProps {
  title: string
  description: string
  learnMoreUrl: string
  label?: string
}

export function UsageHint({title, description, learnMoreUrl, label}: UsageHintProps) {
  const {close: closeOverlay, isOpen: isOverlayOpen, open: openOverlay} = useOverlayControls()
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
          aria-label={label || title}
          aria-labelledby={undefined}
          data-testid="usage-hint-button"
        />
      )}
      side="outside-top"
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
        <Link href={learnMoreUrl} data-testid="learn-more-link">
          Learn more
        </Link>
      </Stack>
    </AnchoredOverlay>
  )
}
