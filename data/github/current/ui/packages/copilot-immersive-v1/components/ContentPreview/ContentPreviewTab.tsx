import {sendEvent} from '@github-ui/hydro-analytics'
import {CodeIcon, ImageIcon, IssueDraftIcon, IssueOpenedIcon, MarkdownIcon, XIcon} from '@primer/octicons-react'
import {IconButton, Spinner} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {forwardRef, useRef} from 'react'

import type {File, PreviewableContent} from './content-preview-types'
import styles from './ContentPreviewTab.module.css'

interface ContentPreviewTabProps extends React.HTMLAttributes<HTMLButtonElement> {
  isActive?: boolean
  onClose?: () => void
  item: PreviewableContent
  controlHintId: string
  tabPanelId?: string
}

function CodeTabIcon({file}: {file: File}) {
  if (file.isStreaming) {
    return <Spinner size="small" />
  }
  switch (file.language) {
    case 'markdown':
      return <MarkdownIcon />
    default:
      return <CodeIcon />
  }
}

function TabIcon({item}: {item: PreviewableContent}) {
  switch (item.type) {
    case 'file':
      return <CodeTabIcon file={item} />
    case 'image':
      return <ImageIcon />
    case 'issue':
      return <IssueOpenedIcon />
    case 'new-issue':
      return <IssueDraftIcon />
    default:
      return null
  }
}

export const ContentPreviewTab = forwardRef<HTMLButtonElement, ContentPreviewTabProps>(function ContentPreviewTab(
  {onClick, onClose, isActive, item, controlHintId, tabPanelId, ...rest},
  ref,
) {
  const closeTab = () => {
    if (onClose) onClose()
    sendEvent('dotcom_chat.activate', {target: 'BROWSER_TAB_CLOSE', mode: 'immersive'})
  }

  const closeButtonRef = useRef<HTMLButtonElement>(null)

  const title = item.name

  return (
    <div className={styles.tabContainer}>
      <div className={clsx(styles.tabContent, {[styles.isActive]: isActive})}>
        <button
          className={styles.mainButton}
          type="button"
          role="tab"
          aria-selected={isActive ? 'true' : undefined}
          aria-describedby={controlHintId}
          aria-controls={tabPanelId}
          onClick={e => {
            if (onClick) onClick(e)
            sendEvent('dotcom_chat.activate', {target: 'BROWSER_TAB_SELECT', mode: 'immersive'})
          }}
          onKeyDown={e => {
            switch (e.key.toLowerCase()) {
              case 'delete':
              case 'backspace':
                closeTab()
                break
              case 'tab':
                if (e.shiftKey) break
                e.preventDefault()
                closeButtonRef.current?.focus()
            }
          }}
          onAuxClick={e => {
            // middle mouse button
            if (e.button === 1) closeTab()
          }}
          ref={ref}
          {...rest}
        >
          <span className={styles.icon}>
            <TabIcon item={item} />
          </span>
          {/* The data-title attribute and respective CSS is required to set the width of the title using a semibold
          font-weight. This ensures that switching between tabs with different font-weight won't change the width
          of a tab because a thicker font-weight adds to the width of the element. */}
          <span className={styles.title} data-title={title} data-testid={`content-preview-tab-${item.id}`}>
            {title}
          </span>
        </button>
        <div className={styles.closeButton}>
          {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
          <IconButton
            icon={XIcon}
            size="small"
            variant="invisible"
            aria-label={`Close ${title}`}
            aria-hidden
            tabIndex={-1}
            unsafeDisableTooltip
            onClick={closeTab}
            ref={closeButtonRef}
          />
        </div>
      </div>
    </div>
  )
})
