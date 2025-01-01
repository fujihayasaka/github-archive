import {type ReactNode, type RefObject, useMemo} from 'react'

import {type ActionBarContentContextProps, ActionBarContentProvider} from './ActionBarContentContext'
import {ActionBarRefProvider} from './ActionBarRefContext'
import {ActionBarResizeProvider, type ActionBarResizeProviderValueProps} from './ActionBarResizeContext'
import type {Density} from './types'
import {gapFromDensity} from './utils'
import {VisibleAndOverflowContainer, type VisibleAndOverflowContainerProps} from './VisibleAndOverflowContainer'

const defaultDensity: Density = 'normal'

export type ActionBarProps = Omit<ActionBarContentContextProps, 'gap'> &
  Pick<VisibleAndOverflowContainerProps, 'overflowMenuToggleProps' | 'className' | 'style'> & {
    /**
     * Any other elements to display in the action bar that shouldn't be collapsed based on available space.
     */
    children?: ReactNode
    /**
     * Spacing between individual items in the action bar, as well as between items and the overflow menu toggle
     * button. Defaults to 'normal'.
     */
    density?: Density

    /**
     * A ref to the element that should be used as the anchor for the overflow menu.
     */
    anchorRef?: RefObject<HTMLElement>
  }

const InternalActionBar = ({children, ...props}: VisibleAndOverflowContainerProps) => (
  <VisibleAndOverflowContainer {...props}>{children}</VisibleAndOverflowContainer>
)

export const ActionBar = ({
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  actions = [],
  staticMenuActions,
  overflowMenuToggleProps,
  children,
  label,
  variant,
  density = defaultDensity,
  anchorRef,
  className,
  style,
}: ActionBarProps) => {
  const contentProviderValue = useMemo<ActionBarContentContextProps>(
    () => ({actions, staticMenuActions, variant, label, gap: gapFromDensity(density)}),
    [actions, staticMenuActions, variant, label, density],
  )
  const resizeProviderValue = useMemo<ActionBarResizeProviderValueProps>(
    () => ({actionKeys: actions.map(action => action.key)}),
    [actions],
  )

  const hasStaticMenuActions = staticMenuActions && staticMenuActions.length > 0
  const hasActions = actions && actions.length > 0

  if (!hasActions && !hasStaticMenuActions) return null

  const internalActionBarProps = {
    overflowMenuToggleProps,
    className,
    style,
  }

  return (
    <ActionBarRefProvider value={{anchorRef}}>
      <ActionBarContentProvider value={contentProviderValue}>
        {/* Optimize performance by including resize provider only when `actions` are provided */}
        {hasActions ? (
          <ActionBarResizeProvider value={resizeProviderValue}>
            <InternalActionBar {...internalActionBarProps}>{children}</InternalActionBar>
          </ActionBarResizeProvider>
        ) : (
          <InternalActionBar {...internalActionBarProps}>{children}</InternalActionBar>
        )}
      </ActionBarContentProvider>
    </ActionBarRefProvider>
  )
}
