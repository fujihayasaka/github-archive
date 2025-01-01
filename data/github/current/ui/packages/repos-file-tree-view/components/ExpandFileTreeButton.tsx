import {DuplicateOnKeydownButton} from '@github-ui/code-view-shared/components/DuplicateOnKeydownButton'
import {useShortcut} from '@github-ui/code-view-shared/hooks/shortcuts'
import {ExpandButton} from '@github-ui/expand-button'
import {useClientValue} from '@github-ui/use-client-value'
import {ArrowLeftIcon} from '@primer/octicons-react'
import {Button, type ButtonProps} from '@primer/react'
import type {TooltipProps} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import React from 'react'

import styles from './ExpandFileTreeButton.module.css'

export interface ExpandFileTreeButtonProps extends Pick<ButtonProps, 'variant'> {
  expanded?: boolean
  onToggleExpanded: React.MouseEventHandler<HTMLButtonElement>
  className?: string
  ariaControls: string
  textAreaId: string
  useFilesButtonBreakpoint?: boolean
  getTooltipDirection?: (expanded?: boolean) => TooltipProps['direction']
}

export const ExpandFileTreeButton = React.forwardRef(
  (
    {
      expanded,
      onToggleExpanded,
      className,
      ariaControls,
      textAreaId,
      useFilesButtonBreakpoint = true,
      variant,
      getTooltipDirection,
    }: ExpandFileTreeButtonProps,
    ref: React.ForwardedRef<HTMLButtonElement>,
  ) => {
    const {toggleTreeShortcut} = useShortcut()
    const [isSSR] = useClientValue(() => false, true, [])
    const tooltipDirection = getTooltipDirection?.(expanded) ?? 'se'

    return (
      <>
        {/* on the server, the expanded value will purely be whatever their saved
    setting is, which might be expanded. On mobile widths we don't ever default to
    having the tree expanded, so on the server we need to just hard code it to
    show the regular not expanded version of everything*/}
        {useFilesButtonBreakpoint && (!expanded || isSSR) && (
          <Button
            aria-label="Expand file tree"
            leadingVisual={ArrowLeftIcon}
            data-hotkey={toggleTreeShortcut.hotkey}
            data-testid="expand-file-tree-button-mobile"
            ref={ref}
            onClick={onToggleExpanded}
            variant={variant ?? 'invisible'}
            className={styles.Button_1}
          >
            Files
          </Button>
        )}
        <ExpandButton
          dataHotkey={toggleTreeShortcut.hotkey}
          className={clsx(className, 'position-relative', styles.expandButton, {
            [styles.filesButtonBreakpoint]: useFilesButtonBreakpoint && (!expanded || isSSR),
          })}
          expanded={expanded}
          alignment="left"
          ariaLabel={expanded ? 'Collapse file tree' : 'Expand file tree'}
          tooltipDirection={tooltipDirection}
          testid="file-tree-button"
          ariaControls={ariaControls}
          ref={ref}
          variant={variant}
          onToggleExpanded={onToggleExpanded}
        />
        <DuplicateOnKeydownButton
          buttonFocusId={textAreaId}
          buttonHotkey={toggleTreeShortcut.hotkey}
          onButtonClick={onToggleExpanded}
          onlyAddHotkeyScopeButton
        />
      </>
    )
  },
)

ExpandFileTreeButton.displayName = 'ExpandFileTreeButton'
