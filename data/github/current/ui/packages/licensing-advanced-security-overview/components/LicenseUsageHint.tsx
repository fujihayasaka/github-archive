import {AnchoredOverlay, IconButton, Stack, Text} from '@primer/react'
import {clsx} from 'clsx'
import styles from './LicenseUsageHint.module.css'
import {InfoIcon} from '@primer/octicons-react'
import {useOverlayControls} from '../hooks/use-overlay-controls'

export interface LicenseUsageHintProps {
  title: string
  description: string
  children?: React.ReactNode
}

export function LicenseUsageHint({title, description, children}: LicenseUsageHintProps) {
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
          aria-label={title}
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
        {children}
      </Stack>
    </AnchoredOverlay>
  )
}
