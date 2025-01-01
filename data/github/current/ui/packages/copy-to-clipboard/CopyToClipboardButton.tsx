import {usePortalTooltip, type PortalTooltipProps} from '@github-ui/portal-tooltip/use-portal-tooltip'
import useIsMounted from '@github-ui/use-is-mounted'
import type {Icon} from '@primer/octicons-react'
import {CheckIcon, CopyIcon} from '@primer/octicons-react'
import type {ButtonProps, SxProp} from '@primer/react'
import {IconButton} from '@primer/react'
import type {TooltipProps} from '@primer/react/deprecated'
import {Octicon} from '@primer/react/deprecated'
import React from 'react'
import {clsx} from 'clsx'
import {Tooltip} from '@primer/react/next'
import {announce} from '@github-ui/aria-live'

import {copyText} from './copy'

type VariantType = NonNullable<ButtonProps['variant']>

const copyConfirmationMsDelay = 2000

export interface CopyToClipboardButtonProps extends SxProp {
  /**
   * Octicon that is displayed on the copy button
   *
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
  tooltipProps?: TooltipProps | PortalTooltipProps
  /**
   * Which icon button variant to use
   */
  iconButtonVariant?: VariantType
  /**
   * Text that will be displayed in the tooltip
   */
  ariaLabel?: string | null
  /**
   * If the button should be accessible or not
   */
  accessibleButton?: boolean
  /**
   * Whether or not to use the portal tooltip
   */
  hasPortalTooltip?: boolean
  /**
   * Whether or not to avoid using styled-components when rendering a portalled tooltip button
   * If true, underlying icon button will be rendered with <button> + Primer CSS
   * If false, underlying icon button will be rendered with Primer's <IconButton>
   * Providing a custom sx prop will override this behavior and use styled-components
   * @default false
   */
  avoidStyledComponent?: boolean
  /**
   * Apply Primer CSS utility classes to button
   * See https://primer.style/foundations/css-utilities
   */
  className?: string
}

export function CopyToClipboardButton({
  icon = CopyIcon,
  size = 'medium',
  onCopy,
  sx,
  textToCopy,
  tooltipProps,
  iconButtonVariant = 'invisible',
  ariaLabel,
  accessibleButton,
  hasPortalTooltip = false,
  avoidStyledComponent = false,
  className,
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

  const label = ariaLabel ?? `Copy ${textToCopy} to clipboard`
  const visibleTooltipText = copied ? 'Copied!' : label

  // We are adding `aria-hidden="true"` to the tooltip because the button has an accessible name.
  // We don't want to override that when the visible text updates to "Copied!" because
  // our screen reader announcement will let the user know their action was successful in the most
  // consistent way across browsers and assistive technology.
  tooltipProps = {...tooltipProps, 'aria-hidden': 'true'}

  if (hasPortalTooltip) {
    return (
      <PortalTooltipCopyButton
        label={label}
        size={size}
        textToCopy={textToCopy}
        copied={copied}
        onClickCopy={onClickCopy}
        tooltipProps={tooltipProps}
        text={visibleTooltipText}
        avoidStyledComponent={avoidStyledComponent}
        iconButtonVariant={iconButtonVariant}
        sx={sx}
        className={className}
      />
    )
  }
  return (
    <Tooltip
      className="position-absolute"
      text={visibleTooltipText}
      aria-label={label}
      type={'label'}
      {...tooltipProps}
    >
      {/* @ts-expect-error aria-labelledby is automatically added at runtime */}
      <IconButton
        icon={copied ? CheckIcon : icon}
        variant={iconButtonVariant}
        size={size}
        tabIndex={accessibleButton === false ? -1 : 0}
        className={clsx(copied ? 'color-fg-success' : undefined, className)}
        sx={{...sx}}
        onClick={onClickCopy}
      />
    </Tooltip>
  )
}

interface PortalTooltipCopyButtonProps extends CopyToClipboardButtonProps {
  /**
   * Text that will be displayed in the tooltip
   */
  label: string
  /**
   * Copy state
   */
  copied: boolean
  /**
   * Function to call when copy button is clicked
   */
  onClickCopy: () => void
  /**
   * Text that should be passed in for the visible label when it is different than the aria-label
   */
  text?: string
}

function PortalTooltipCopyButton({
  icon = CopyIcon,
  size = 'medium',
  label,
  accessibleButton,
  copied,
  onClickCopy,
  text,
  tooltipProps,
  iconButtonVariant,
  sx,
  avoidStyledComponent = false,
  className,
}: PortalTooltipCopyButtonProps) {
  const contentRef = React.useRef<HTMLDivElement>(null)
  const [buttonContentProps, buttonTooltipElement] = usePortalTooltip({
    contentRef,
    'aria-label': label,
    text,
    ...tooltipProps,
  })

  return (
    <div ref={contentRef} {...buttonContentProps}>
      <PortalCopyIconButton
        icon={icon}
        size={size}
        label={label}
        copied={copied}
        onClickCopy={onClickCopy}
        accessibleButton={accessibleButton}
        avoidStyledComponent={avoidStyledComponent}
        className={className}
        iconButtonVariant={iconButtonVariant}
        sx={sx}
      />
      {buttonTooltipElement}
    </div>
  )
}

type CopyIconButtonProps = Pick<
  PortalTooltipCopyButtonProps,
  | 'icon'
  | 'size'
  | 'label'
  | 'accessibleButton'
  | 'copied'
  | 'onClickCopy'
  | 'iconButtonVariant'
  | 'sx'
  | 'avoidStyledComponent'
  | 'className'
>

function PortalCopyIconButton({
  icon = CopyIcon,
  size = 'medium',
  label,
  accessibleButton,
  copied,
  onClickCopy,
  iconButtonVariant,
  sx,
  avoidStyledComponent = false,
  className,
}: CopyIconButtonProps) {
  if (avoidStyledComponent && !sx) {
    return (
      <button
        aria-label={label}
        tabIndex={accessibleButton === false ? -1 : 0}
        className={clsx(
          `Button Button--iconOnly Button--invisible Button--${size} ${copied ? 'color-fg-success' : ''}`,
          className,
        )}
        onClick={onClickCopy}
      >
        {copied ? <CheckIcon /> : <Octicon icon={icon} />}
      </button>
    )
  }

  return (
    // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
    <IconButton
      unsafeDisableTooltip
      aria-label={label}
      icon={copied ? CheckIcon : icon}
      variant={iconButtonVariant}
      size={size}
      tabIndex={accessibleButton === false ? -1 : 0}
      className={copied ? 'color-fg-success' : undefined}
      sx={{...sx}}
      onClick={onClickCopy}
    />
  )
}
