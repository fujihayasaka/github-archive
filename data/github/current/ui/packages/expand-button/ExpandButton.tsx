import {SidebarCollapseIcon, SidebarExpandIcon} from '@primer/octicons-react'
import {IconButton, type ButtonProps, type IconButtonProps} from '@primer/react'
import {clsx} from 'clsx'
import React from 'react'

export interface ExpandButtonProps extends Pick<ButtonProps, 'variant'> {
  expanded?: boolean
  onToggleExpanded: React.MouseEventHandler<HTMLButtonElement>
  testid: string
  alignment: 'left' | 'right'
  ariaLabel: string
  ariaControls: string
  dataHotkey?: string
  className?: string
  size?: ButtonProps['size']
  tooltipDirection?: IconButtonProps['tooltipDirection']
}

export const ExpandButton = React.forwardRef(
  (
    {
      expanded,
      testid,
      ariaLabel,
      ariaControls,
      onToggleExpanded,
      alignment,
      dataHotkey,
      className,
      size,
      tooltipDirection,
      variant,
    }: ExpandButtonProps,
    ref: React.ForwardedRef<HTMLButtonElement>,
  ) => (
    <IconButton
      aria-label={ariaLabel}
      tooltipDirection={tooltipDirection}
      ref={ref}
      data-testid={expanded ? `collapse-${testid}` : `expand-${testid}`}
      aria-expanded={expanded}
      aria-controls={ariaControls}
      icon={
        expanded
          ? alignment === 'left'
            ? SidebarExpandIcon
            : SidebarCollapseIcon
          : alignment === 'left'
            ? SidebarCollapseIcon
            : SidebarExpandIcon
      }
      data-hotkey={dataHotkey}
      onClick={e => {
        onToggleExpanded(e)
      }}
      variant={variant ?? 'invisible'}
      size={size}
      className={clsx(className, 'fgColor-muted')}
    />
  ),
)

ExpandButton.displayName = 'ExpandButton'
