import useIsMounted from '@github-ui/use-is-mounted'
import type {Icon} from '@primer/octicons-react'
import {CheckIcon, CopyIcon} from '@primer/octicons-react'
import type {ButtonProps, IconButtonProps, TooltipProps} from '@primer/react'
import {IconButton} from '@primer/react'
import React, {useId} from 'react'
import {clsx} from 'clsx'
import {Tooltip} from '@primer/react/next'
import {announce} from '@github-ui/aria-live'

import {copyText} from './copy'

import styles from './CopyToClipboardButton.module.css'

type VariantType = NonNullable<ButtonProps['variant']>

const copyConfirmationMsDelay = 2000

export interface CopyToClipboardButtonProps
  extends Omit<
    IconButtonProps,
    'icon' | 'onClick' | 'aria-labelledby' | 'aria-label' | 'unsafeDisableTooltip' | 'tooltipDirection'
  > {
  /**
   * Octicon that is displayed on the copy button
   * @default CopyIcon
   */
  icon?: Icon
  /**
   * Size of the button, passed to IconButton
   */
  size?: 'small' | 'medium' | 'large'
  /**
   * Optional callback that is invoked when the user clicks the copy button
   */
  onCopy?: () => void
  /**
   * Text that will be copied to the clipboard
   */
  textToCopy: string
  /**
   * Props that will be applied to tooltips
   */
  tooltipProps?: Omit<TooltipProps, 'text' | 'aria-label' | 'type' | 'id' | 'aria-hidden'>
  /**
   * Which icon button variant to use
   * @default "invisible"
   */
  variant?: VariantType
  /**
   * Text that will be displayed in the tooltip
   * @default `Copy "${textToCopy}" to clipboard`
   */
  ariaLabel?: string
}

export function CopyToClipboardButton({
  icon = CopyIcon,
  size = 'medium',
  onCopy,
  textToCopy,
  tooltipProps,
  variant = 'invisible',
  ariaLabel,
  className,
  disabled,
  ...forwardProps
}: CopyToClipboardButtonProps) {
  const [copied, setCopied] = React.useState(false)
  const isMounted = useIsMounted()
  const onClickCopy = () => {
    setCopied(true)
    announce('Copied!')
    void copyText(textToCopy)
    onCopy?.()
    setTimeout(() => isMounted() && setCopied(false), copyConfirmationMsDelay)
  }

  const label = ariaLabel ?? `Copy "${textToCopy}" to clipboard`
  const visibleTooltipText = copied ? 'Copied!' : label

  const sharedProps = {
    size,
    variant,
    onClick: onClickCopy,
    icon: copied ? CheckIcon : icon,
    className: clsx(copied ? 'color-fg-success' : undefined, className),
    ...forwardProps,
  }

  const tooltipId = useId()

  // Tooltip isn't allowed to wrap a disabled button
  return disabled ? (
    <IconButton
      {...sharedProps}
      // Without a tooltip we need an explicit label
      aria-label={label}
      disabled
    />
  ) : (
    <Tooltip
      text={visibleTooltipText}
      aria-label={label}
      type="label"
      id={tooltipId}
      // We are adding `aria-hidden="true"` to the tooltip because the button has an accessible name.
      // We don't want to override that when the visible text updates to "Copied!" because
      // our screen reader announcement will let the user know their action was successful in the most
      // consistent way across browsers and assistive technology.
      aria-hidden
      {...tooltipProps}
      className={clsx(styles.tooltip, tooltipProps?.className)}
    >
      <IconButton {...sharedProps} aria-labelledby={tooltipId} />
    </Tooltip>
  )
}
