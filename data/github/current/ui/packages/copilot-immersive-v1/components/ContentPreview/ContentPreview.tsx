import {useChatState, useChatStateValue} from '@github-ui/copilot-chat/CopilotChatContext'
import {useIsScrolledToEnd} from '@github-ui/copilot-chat/hooks/use-is-scrolled-to-end'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {usePlugin} from '@github-ui/copilot-chat/plugin/registry'
import {sendEvent} from '@github-ui/hydro-analytics'
import {usePreviousValue} from '@github-ui/use-previous-value'
import {FocusKeys} from '@primer/behaviors'
import {FileZipIcon, KebabHorizontalIcon, SidebarCollapseIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, useFocusZone} from '@primer/react'
import {downloadZip} from 'client-zip'
import {clsx} from 'clsx'
import {type RefObject, useCallback, useEffect, useId, useRef, type WheelEvent} from 'react'

import type {PreviewableContent} from './content-preview-types'
import styles from './ContentPreview.module.css'
import {useContentPreview} from './ContentPreviewContext'
import {ContentPreviewTab} from './ContentPreviewTab'
import {CreateIssuePreview} from './CreateIssuePreview'
import {downloadFile} from './download-file'
import {EmptyState} from './EmptyState'
import {FilePreview} from './FilePreview'
import {ImagePreview} from './ImagePreview'
import {IssuePreview} from './IssuePreview'
import {LoadingState} from './LoadingState'
import {sendContentPreviewEvent} from './telemetry'

function ContentPreviewItem({
  isOpening,
  onClose,
  previewItem,
}: {
  isOpening: boolean
  onClose: () => void
  previewItem: PreviewableContent
}) {
  switch (previewItem.type) {
    case 'file':
      return <FilePreview file={previewItem} onClose={onClose} />
    case 'issue':
      return <IssuePreview isPreviewOpening={isOpening} issue={previewItem} onClose={onClose} />
    case 'new-issue':
      return <CreateIssuePreview isPreviewOpening={isOpening} issue={previewItem} onClose={onClose} />
    case 'image':
      return <ImagePreview image={previewItem} />
    default:
      return null
  }
}

interface ContentPreviewProps {
  /** Element to focus on close. */
  returnFocusRef: RefObject<HTMLElement | null>
}

export function ContentPreview({returnFocusRef}: ContentPreviewProps) {
  const {
    items,
    openItems,
    selectedItem,
    openItem,
    closeItem,
    closePreviewPane,
    showLoadingState,
    previewPaneOpen: isOpen,
  } = useContentPreview()
  const prevIsOpen = usePreviousValue(isOpen)
  const isOpening = isOpen && !prevIsOpen
  const isClosing = prevIsOpen && !isOpen
  const openFiles = openItems.map(itemId => items.get(itemId)).filter(item => item?.type === 'file')
  const activePlugin = usePlugin(useChatStateValue('activePlugin'))

  const labelId = useId()
  const activeTabId = useId()
  const selectedTabPanelId = useId()
  const closeTabControlHintId = useId()

  const openItemInstances = openItems.map(key => items.get(key)).filter(item => !!item)

  useEffect(() => {
    if (isClosing) returnFocusRef.current?.focus()
  }, [isClosing, returnFocusRef])

  const downloadAll = async () => {
    const files = openFiles.map(item => new File([item.value], item.name))
    const blob = await downloadZip(files).blob()
    downloadFile(new File([blob], 'files.zip'))
  }

  const selectedItemInstance = openItemInstances.find(item => item.id === selectedItem) ?? openItemInstances[0]
  const handleClose = useCallback(
    () => selectedItemInstance && closeItem(selectedItemInstance.id),
    [closeItem, selectedItemInstance],
  )

  const tabsRef = useRef<Array<HTMLButtonElement | null>>([])

  const tablistRef = useRef<HTMLDivElement>(null)
  useFocusZone(
    {
      containerRef: tablistRef,
      focusableElementFilter: el => el.role === 'tab',
      bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
      focusInStrategy: 'first',
      focusOutBehavior: 'wrap',
    },
    [openItemInstances],
  )
  const tabsHasOverflow = !useIsScrolledToEnd(tablistRef)

  const onTabsWheel = (event: WheelEvent<HTMLDivElement>) => {
    if (!event.deltaY) return
    event.preventDefault()
    event.currentTarget.scrollLeft += event.deltaY
  }

  const closeTab = (i: number) => {
    const item = openItemInstances[i]
    if (!item) return

    const nextFocusTarget = tabsRef.current[i + 1] ?? tabsRef.current[i - 1] ?? tablistRef.current
    nextFocusTarget?.focus()

    const isOnly = openItemInstances.length === 1
    closeItem(item.id)
    if (isOnly) closePreviewPane()
    sendContentPreviewEvent('filePreviewTab.close', item)
  }

  const menuButton = openFiles.length > 1 && (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton icon={KebabHorizontalIcon} aria-label="More options" variant="invisible" />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList>
          <ActionList.Item onSelect={downloadAll}>
            <ActionList.LeadingVisual>
              <FileZipIcon />
            </ActionList.LeadingVisual>
            Download all files
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )

  return (
    <aside aria-labelledby={labelId} className={styles.container} tabIndex={-1}>
      <h2 id={labelId} className="sr-only">
        Workbench
      </h2>
      {activePlugin?.PreviewAreaComponent ? (
        <PluginContent plugin={activePlugin} closePreviewPane={closePreviewPane} />
      ) : (
        <>
          <div className={styles.toolbar}>
            <div className={clsx(styles.actions, styles.rightDivider)}>
              <IconButton
                variant="invisible"
                icon={SidebarCollapseIcon}
                aria-label="Close file browser"
                onClick={() => {
                  closePreviewPane()
                  sendEvent('dotcom_chat.activate', {target: 'BROWSER_CLOSE', mode: 'immersive'})
                }}
              />
            </div>
            <div className={styles.tabsContainer}>
              <div
                className={styles.tabs}
                role="tablist"
                aria-labelledby={labelId}
                ref={tablistRef}
                tabIndex={-1}
                onWheel={onTabsWheel}
              >
                {openItemInstances.map((item, i) => (
                  <ContentPreviewTab
                    id={item.id === selectedItem ? activeTabId : undefined}
                    tabPanelId={item.id === selectedItem ? selectedTabPanelId : undefined}
                    controlHintId={closeTabControlHintId}
                    key={item.id}
                    isActive={item.id === selectedItem}
                    onClick={() => {
                      openItem(item.id)
                      sendContentPreviewEvent('filePreviewTab.click', item)
                    }}
                    onClose={() => closeTab(i)}
                    item={item}
                    ref={el => {
                      tabsRef.current[i] = el
                    }}
                  />
                ))}
                <span id={closeTabControlHintId} aria-hidden="true" className="sr-only">
                  Press Delete to close.
                </span>
                <span />
              </div>
            </div>
            {menuButton && (
              <div className={clsx(styles.actions, tabsHasOverflow && styles.leftDivider)}>{menuButton}</div>
            )}
          </div>

          <div className={styles.content} role="tabpanel" id={selectedTabPanelId} aria-labelledby={activeTabId}>
            {showLoadingState ? (
              <LoadingState />
            ) : selectedItemInstance ? (
              <ContentPreviewItem isOpening={isOpening} previewItem={selectedItemInstance} onClose={handleClose} />
            ) : (
              <EmptyState />
            )}
          </div>
        </>
      )}
    </aside>
  )
}

function PluginContent({plugin, closePreviewPane}: {plugin: ImmersivePlugin; closePreviewPane: () => void}) {
  const state = useChatState()
  const {PreviewAreaComponent} = plugin
  return PreviewAreaComponent ? (
    <PreviewAreaComponent
      key={state.selectedThreadID}
      chatState={state}
      plugin={plugin}
      closePreviewPane={closePreviewPane}
    />
  ) : null
}
