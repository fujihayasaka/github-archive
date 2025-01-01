import {SidebarCollapseIcon, SidebarExpandIcon} from '@primer/octicons-react'
import {IconButton, type ButtonProps} from '@primer/react'
import type {TooltipProps} from '@primer/react/deprecated'
import {Tooltip} from '@primer/react/deprecated'
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
  tooltipDirection?: TooltipProps['direction']
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
      tooltipDirection,
      variant,
    }: ExpandButtonProps,
    ref: React.ForwardedRef<HTMLButtonElement>,
  ) => (
    <Tooltip aria-label={ariaLabel} id={`expand-button-${testid}`} direction={tooltipDirection}>
      {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
      <IconButton
        unsafeDisableTooltip
        ref={ref}
        data-testid={expanded ? `collapse-${testid}` : `expand-${testid}`}
        aria-labelledby={`expand-button-${testid}`}
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
        className={clsx(className, 'fgColor-muted')}
      />
    </Tooltip>
  ),
)

ExpandButton.displayName = 'ExpandButton'
