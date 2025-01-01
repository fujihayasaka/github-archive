import {noop} from '@github-ui/noop'
import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionMenu, Button, ButtonGroup, IconButton, type ButtonProps} from '@primer/react'
import {useEffect, useRef, useState, type ComponentProps} from 'react'
import {Tooltip} from '@primer/react/next'

type ButtonWithDropdownProps = {
  /**
   * The class name to apply to the root element
   */
  className?: string
  /**
   * The text to render in the primary button
   */
  children?: string | JSX.Element
  /**
   * Action list component that renders when the secondary icon button is activated
   */
  actionList?: JSX.Element
  /**
   * Whether to make both primary and secondary buttons inactive
   */
  inactive?: boolean
  /**
   * Tooltip text if the buttons are inactive
   */
  inactiveTooltipText?: string
  /**
   * Optional tooltip direction. If not supplied, defaults to 'ne'
   */
  inactiveTooltipDirection?: ComponentProps<typeof Tooltip>['direction']
  /**
   * Optional override that makes the secondary button active even if the inactive prop is set to false
   */
  secondaryButtonActive?: boolean
  /**
   * The aria-label for the secondary button
   */
  secondaryButtonAriaLabel: string
  /**
   * Function to handle the primary button click
   */
  onPrimaryButtonClick: () => void
  /**
   * If buttons should be shown in their primary variant
   */
  isPrimary?: boolean
  /**
   * Whether to focus the primary button on render
   */
  shouldFocusPrimaryButton?: boolean
  /**
   * Optional function to handle focus
   */
  onFocusPrimaryButton?: () => void
  /**
   * Optional boolean to hide secondaryButton
   */
  hideSecondaryButton?: boolean
} & Pick<ButtonProps, 'variant' | 'loading' | 'loadingAnnouncement'>

/**
 * Renders a primary button with a secondary icon button dropdown
 */
export function ButtonWithDropdown({
  className,
  children,
  actionList,
  inactive,
  inactiveTooltipText,
  inactiveTooltipDirection = 'ne',
  loading,
  loadingAnnouncement,
  secondaryButtonActive,
  secondaryButtonAriaLabel,
  onPrimaryButtonClick,
  shouldFocusPrimaryButton,
  onFocusPrimaryButton,
  isPrimary = false,
  hideSecondaryButton = false,
}: ButtonWithDropdownProps) {
  const primaryButtonRef = useRef<HTMLButtonElement>(null)
  useEffect(() => {
    if (shouldFocusPrimaryButton) {
      primaryButtonRef.current?.focus()
      onFocusPrimaryButton?.()
    }
  }, [shouldFocusPrimaryButton, onFocusPrimaryButton])

  // The button group constrains the width of the overlay, so we set it to a fixed width
  const overlayWidth = '320px'
  const buttonVariant = isPrimary ? 'primary' : 'default'

  const [isOpen, setIsOpen] = useState(false)

  const secondaryButtonInactive = inactive && !secondaryButtonActive

  // If loading is defined, we want to let Primer handle loading state of the button
  // Otherwise, use the provided inactive state
  const inactiveProps =
    loading !== undefined
      ? {}
      : {
          inactive,
          'aria-disabled': inactive,
        }

  const buttonContent = (
    <ButtonGroup className={className}>
      <Button
        className="flex-1"
        variant={buttonVariant}
        ref={primaryButtonRef}
        loading={loading}
        loadingAnnouncement={loadingAnnouncement}
        onClick={inactive ? noop : onPrimaryButtonClick}
        {...inactiveProps}
      >
        {children}
      </Button>
      {!hideSecondaryButton && (
        <ActionMenu open={isOpen} onOpenChange={secondaryButtonInactive ? noop : open => setIsOpen(open)}>
          <ActionMenu.Anchor>
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton
              className="flex-0"
              variant={buttonVariant}
              unsafeDisableTooltip
              aria-label={secondaryButtonAriaLabel}
              aria-disabled={secondaryButtonInactive}
              inactive={secondaryButtonInactive}
              icon={TriangleDownIcon}
            />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay align="end" sx={{width: overlayWidth}}>
            {actionList}
          </ActionMenu.Overlay>
        </ActionMenu>
      )}
    </ButtonGroup>
  )

  if (inactive && inactiveTooltipText) {
    return (
      <Tooltip text={inactiveTooltipText} direction={inactiveTooltipDirection}>
        {buttonContent}
      </Tooltip>
    )
  }

  return buttonContent
}
