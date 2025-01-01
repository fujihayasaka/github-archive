import {ActionBar as GitHubUiActionBar, type ActionBarProps as GitHubUiActionBarProps} from '@github-ui/action-bar'
import {testIdProps} from '@github-ui/test-id-props'
import {clsx} from 'clsx'

import styles from './ActionBar.module.css'

// Require actionsLabel if actions are provided, and vice versa.
type ActionsLabelProps =
  | {
      /**
       * Description of the controls found in the action bar, e.g., "Issue actions", "Markdown formatting tools".
       * Will be used in a hidden label for accessibility purposes. Defaults to the title for the ListView.
       */
      actionsLabel: GitHubUiActionBarProps['label']
      /**
       * The controls to show in the action bar. These will move into a dropdown menu when the screen isn't big enough to
       * fit them side by side.
       */
      actions: GitHubUiActionBarProps['actions']
    }
  | {actionsLabel?: undefined; actions?: undefined}

export type NestedListViewHeaderActionBarProps = ActionsLabelProps &
  Omit<GitHubUiActionBarProps, 'actions' | 'label'> & {
    className?: string
  }

export const NestedListViewHeaderActionBar = ({
  actions,
  children,
  density = 'normal',
  actionsLabel,
  className,
}: NestedListViewHeaderActionBarProps) => {
  const nonCollapsibleActions = children

  if (actions && actions.length > 0) {
    return (
      <GitHubUiActionBar
        label={actionsLabel?.trim()}
        actions={actions}
        density={density}
        className={className}
        {...testIdProps('list-view-actions')}
      >
        {nonCollapsibleActions}
      </GitHubUiActionBar>
    )
  }

  return (
    <div
      {...testIdProps('list-view-actions')}
      className={clsx(styles.actionBar, styles[`${density}Density`], className)}
    >
      {nonCollapsibleActions}
    </div>
  )
}
