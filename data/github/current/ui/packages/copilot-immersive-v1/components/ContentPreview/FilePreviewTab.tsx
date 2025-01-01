import {sendEvent} from '@github-ui/hydro-analytics'
import {XIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'

import styles from './FilePreviewTab.module.css'

type CodeViewTabProps = {
  isActive?: boolean
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void
  onClose?: (e: React.MouseEvent<HTMLButtonElement>) => void
} & React.HTMLAttributes<HTMLButtonElement>

export function FilePreviewTab({onClick, onClose, isActive, children, ...rest}: CodeViewTabProps) {
  return (
    <div className={styles.tabContainer}>
      <div className={clsx(styles.tabContent, {[styles.isActive]: isActive})}>
        <button
          className={styles.mainButton}
          type="button"
          aria-current={isActive ? 'page' : undefined}
          onClick={e => {
            if (onClick) onClick(e)
            sendEvent('dotcom_chat.activate', {target: 'BROWSER_TAB_SELECT', mode: 'immersive'})
          }}
          {...rest}
        >
          <span className={styles.title}>{children}</span>
        </button>
        <div className={styles.closeButton}>
          {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
          <IconButton
            icon={XIcon}
            variant="invisible"
            aria-label="Close tab"
            unsafeDisableTooltip
            onClick={e => {
              if (onClose) onClose(e)
              sendEvent('dotcom_chat.activate', {target: 'BROWSER_TAB_CLOSE', mode: 'immersive'})
            }}
          />
        </div>
      </div>
    </div>
  )
}
