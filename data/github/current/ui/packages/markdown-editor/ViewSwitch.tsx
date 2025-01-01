import {TabNav} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import styles from './ViewSwitch.module.css'

export type MarkdownViewMode = 'preview' | 'edit'

type ViewSwitchProps = {
  selectedView: MarkdownViewMode
  onViewSelect?: (view: MarkdownViewMode) => void
  disabled?: boolean
  /** Called when the preview should be loaded. */
  onLoadPreview: () => void
}

// no point in memoizing this component because onLoadPreview depends on value, so it would still re-render on every change
export const ViewSwitch = ({selectedView, onViewSelect, onLoadPreview, disabled}: ViewSwitchProps) => {
  // don't get disabled from context - the switch is not disabled when the editor is disabled

  const sharedProps =
    selectedView === 'preview'
      ? {
          onClick: () => onViewSelect?.('edit'),
        }
      : {
          onClick: () => {
            onLoadPreview()
            onViewSelect?.('preview')
          },
          onMouseOver: () => onLoadPreview(),
          onFocus: () => onLoadPreview(),
        }

  return (
    <div className={styles.viewSwitch}>
      <TabNav aria-label="View mode">
        <TabNav.Link
          {...sharedProps}
          as="button"
          selected={selectedView === 'edit'}
          disabled={disabled}
          className={clsx(styles.tabNavLink, selectedView === 'edit' ? styles.editColor : styles.previewColor)}
        >
          Write
        </TabNav.Link>
        <TabNav.Link
          {...sharedProps}
          as="button"
          selected={selectedView === 'preview'}
          disabled={disabled}
          className={clsx(styles.tabNavLink, selectedView === 'preview' ? styles.editColor : styles.previewColor)}
        >
          Preview
        </TabNav.Link>
      </TabNav>
    </div>
  )
}
