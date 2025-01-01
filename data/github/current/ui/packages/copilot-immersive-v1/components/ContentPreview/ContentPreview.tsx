import {sendEvent} from '@github-ui/hydro-analytics'
import {CodeIcon, IssueOpenedIcon, XIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useCallback} from 'react'

import {useContentPreview} from '../../hooks/use-content-preview'
import type {PreviewableContent, PreviewableContentTypes} from '../../utils/content-preview-types'
import {sendContentPreviewEvent} from '../../utils/telemetry'
import styles from './ContentPreview.module.css'
import {FilePreview} from './FilePreview'
import {FilePreviewTab} from './FilePreviewTab'
import {IssuePreview} from './IssuePreview'

function TabIcon({type}: {type: PreviewableContentTypes}) {
  switch (type) {
    case 'file':
      return <CodeIcon />
    case 'issue':
      return <IssueOpenedIcon />
    default:
      return null
  }
}

function ContentPreviewItem({onClose, previewItem}: {onClose: () => void; previewItem: PreviewableContent}) {
  switch (previewItem.type) {
    case 'file':
      return <FilePreview file={previewItem} />
    case 'issue':
      return <IssuePreview issue={previewItem} onClose={onClose} />
    default:
      return null
  }
}

type ContentPreviewProps = {
  onClose: () => void
}

export function ContentPreview({onClose}: ContentPreviewProps) {
  const {previewItems, activePath, setActivePath, updatePreviewItems} = useContentPreview()

  const closePreviewItem = useCallback(
    (path: string) => {
      const newPreviewItems = previewItems.filter(previewItem => previewItem.path !== path)
      updatePreviewItems(newPreviewItems)
      if (activePath === path) {
        // If the active preview item was closed, set the last item as active
        setActivePath(newPreviewItems[newPreviewItems.length - 1]?.path)
      }
    },
    [activePath, previewItems, setActivePath, updatePreviewItems],
  )

  const previewItem = previewItems.find(f => f.path === activePath)

  const closeActiveItem = useCallback(() => {
    if (previewItem) {
      closePreviewItem(previewItem.path)
    }
  }, [closePreviewItem, previewItem])

  if (!previewItem || !activePath) return null

  return (
    <div className={styles.container}>
      <div className={styles.top}>
        <div className={styles.tabContainer}>
          {previewItems.map(item => {
            const isActive = item.path === activePath
            return (
              <FilePreviewTab
                key={item.name}
                isActive={isActive}
                onClick={() => {
                  setActivePath(item.path)
                  sendContentPreviewEvent('filePreviewTab.click', item)
                }}
                onClose={() => {
                  closePreviewItem(item.path)
                  sendContentPreviewEvent('filePreviewTab.close', item)
                }}
              >
                <span className={styles.icon}>
                  <TabIcon type={item.type} />
                </span>
                {item.name}
              </FilePreviewTab>
            )
          })}
        </div>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton
          variant="invisible"
          className={styles.closeButton}
          icon={XIcon}
          aria-label="Close window"
          unsafeDisableTooltip
          onClick={() => {
            onClose()
            sendEvent('dotcom_chat.activate', {target: 'BROWSER_CLOSE', mode: 'immersive'})
          }}
        />
      </div>
      <ContentPreviewItem previewItem={previewItem} onClose={closeActiveItem} />
    </div>
  )
}
