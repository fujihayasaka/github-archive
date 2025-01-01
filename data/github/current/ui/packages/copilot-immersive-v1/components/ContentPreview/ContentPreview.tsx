import {useIsScrolledToEnd} from '@github-ui/copilot-chat/hooks/use-is-scrolled-to-end'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {usePreviousValue} from '@github-ui/use-previous-value'
import {FocusKeys} from '@primer/behaviors'
import {FileZipIcon, KebabHorizontalIcon, SidebarCollapseIcon, XIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, useFocusZone} from '@primer/react'
import {downloadZip} from 'client-zip'
import {clsx} from 'clsx'
import {type RefObject, useCallback, useEffect, useId, useRef, type WheelEvent} from 'react'

import {ErrorFallback} from '../ErrorFallback'
import styles from './ContentPreview.module.css'
import {useContentPreview} from './ContentPreviewContext'
import {ContentPreviewItem} from './ContentPreviewItem'
import {ContentPreviewTab} from './ContentPreviewTab'
import {downloadFile} from './download-file'
import {EmptyState} from './EmptyState'
import {LoadingState} from './LoadingState'
import {sendContentPreviewEvent} from './telemetry'

interface ContentPreviewProps {
  /** Element to focus on close. */
  returnFocusRef: RefObject<HTMLElement | null>
}

function ContentPreviewInner({returnFocusRef}: ContentPreviewProps) {
  const {
    items,
    openItems,
    selectedItem,
    openItem,
    closeItem,
    closeAllItems,
    closePreviewPane,
    showLoadingState,
    previewPaneOpen: isOpen,
  } = useContentPreview()
  const prevIsOpen = usePreviousValue(isOpen)
  const isOpening = isOpen && !prevIsOpen
  const isClosing = prevIsOpen && !isOpen
  const openFiles = openItems.map(itemId => items.get(itemId)).filter(item => item?.type === 'file')

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
    (closePreview = false) => {
      if (selectedItemInstance) {
        const shouldClosePreview = closePreview && openItemInstances.length === 1
        closeItem(selectedItemInstance.id)
        if (shouldClosePreview) {
          closePreviewPane()
          sendEvent('dotcom_chat.activate', {target: 'BROWSER_CLOSE', mode: 'immersive'})
        }
      }
    },
    [closeItem, closePreviewPane, openItemInstances.length, selectedItemInstance],
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

  const closeAll = () => {
    closeAllItems()
    sendEvent('dotcom_chat.activate', {target: 'BROWSER_CLOSE_ALL_TABS', mode: 'immersive'})
  }

  return (
    <>
      <div className={styles.toolbar}>
        <div className={clsx(styles.actions, styles.rightDivider)}>
          <CloseContentPreviewButton />
        </div>
        <div className={styles.tabsContainer}>
          <div
            className={styles.tabs}
            role="tablist"
            aria-label="Workbench items"
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
        {openItems.length > 0 && (
          <div className={clsx(styles.actions, tabsHasOverflow && styles.leftDivider)}>
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton icon={KebabHorizontalIcon} aria-label="More options" variant="invisible" />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay>
                <ActionList>
                  {openFiles.length > 0 && (
                    <ActionList.Item onSelect={downloadAll}>
                      <ActionList.LeadingVisual>
                        <FileZipIcon />
                      </ActionList.LeadingVisual>
                      Download all files
                    </ActionList.Item>
                  )}
                  <ActionList.Item onSelect={closeAll}>
                    <ActionList.LeadingVisual>
                      <XIcon />
                    </ActionList.LeadingVisual>
                    Close all tabs
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </div>
        )}{' '}
      </div>

      <div className={styles.content} role="tabpanel" id={selectedTabPanelId} aria-labelledby={activeTabId}>
        {showLoadingState ? (
          <LoadingState />
        ) : selectedItemInstance ? (
          <ContentPreviewItem isOpening={isOpening} previewItem={selectedItemInstance} onClose={handleClose} />
        ) : (
          <EmptyState isOpening={isOpening} />
        )}
      </div>
    </>
  )
}

function CloseContentPreviewButton() {
  const {closePreviewPane} = useContentPreview()

  return (
    <IconButton
      variant="invisible"
      icon={SidebarCollapseIcon}
      aria-label="Close workbench"
      onClick={() => {
        closePreviewPane()
        sendEvent('dotcom_chat.activate', {target: 'BROWSER_CLOSE', mode: 'immersive'})
      }}
    />
  )
}

function ContentPreviewFallback() {
  return (
    <>
      <div className={styles.toolbar}>
        <div className={clsx(styles.actions, styles.rightDivider)}>
          <CloseContentPreviewButton />
        </div>
      </div>
      <div className={clsx(styles.content)}>
        <ErrorFallback regionName="The workbench" />
      </div>
    </>
  )
}

// We put as much logic into the Inner component as possible so that errors are always caught. We still need some
// container styles around the error boundary though to contain it if it does appear.
export function ContentPreview(props: ContentPreviewProps) {
  const labelId = useId()

  return (
    <div
      aria-labelledby={labelId}
      className={styles.container}
      tabIndex={-1}
      data-testid="content-preview"
      role="dialog"
    >
      <h2 id={labelId} className="sr-only">
        Workbench
      </h2>
      <ErrorBoundary fallback={<ContentPreviewFallback />}>
        <ContentPreviewInner {...props} />
      </ErrorBoundary>
    </div>
  )
}
