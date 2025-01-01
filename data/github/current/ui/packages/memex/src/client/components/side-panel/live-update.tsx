import {testIdProps} from '@github-ui/test-id-props'
import {useQueryClient} from '@tanstack/react-query'
import {memo, useEffect, useRef} from 'react'

import {SidePanelTypeParam} from '../../api/memex-items/side-panel-item'
import {ItemKeyType} from '../../api/side-panel/contracts'
import type {SocketMessageData, SocketMessageIssueData} from '../../api/SocketMessage/contracts'
import {isValidMemexRefreshEventShape, isValidSidePanelRefreshEventShape} from '../../helpers/alive'
import {type Cancellable, useSetTimeout} from '../../hooks/common/timeouts/use-timeout'
import {usePreviousValue} from '../../hooks/common/use-previous-value'
import {useAliveChannel} from '../../hooks/use-alive-channel'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {usePageVisibility} from '../../hooks/use-page-visibility'
import {useSidePanel} from '../../hooks/use-side-panel'
import {useInvalidateSidePanelQueries} from '../../queries/side-panel'
import {useIssueContext} from '../../state-providers/issues/use-issue-context'
import {sidePanelItemNotOnClientQueryKey} from '../../state-providers/memex-items/queries/query-keys'

export const SidePanelLiveUpdate = memo(function SidePanelLiveUpdate() {
  const aliveItemMessageRef = useRef<HTMLSpanElement | null>(null)
  const alivePaneItemMessageRef = useRef<HTMLSpanElement | null>(null)
  const isPageVisible = usePageVisibility()
  const isPageVisiblePrev = usePreviousValue(isPageVisible)
  const {sidePanelMetadata, reloadSidePanelMetadata} = useIssueContext()
  const {reloadPaneItem, sidePanelState} = useSidePanel()
  const {memex_table_without_limits, memex_side_panel_query} = useEnabledFeatures()
  const queryClient = useQueryClient()
  const {invalidateSidePanelQueries} = useInvalidateSidePanelQueries()
  const setReloadMetadataTimeout = useSetTimeout(reloadSidePanelMetadata)
  const setReloadPaneTimeout = useSetTimeout(memex_side_panel_query ? invalidateSidePanelQueries : reloadPaneItem)
  const reloadPaneCancellable = useRef<Cancellable | null>(null)

  const isValidIssueEvent = (data: unknown): data is SocketMessageIssueData => {
    return sidePanelMetadata.itemKey.kind === ItemKeyType.ISSUE && isValidSidePanelRefreshEventShape(data)
  }
  const isValidDraftEvent = (data: unknown): data is SocketMessageData => {
    return (
      sidePanelMetadata.itemKey.kind === ItemKeyType.PROJECT_DRAFT_ISSUE &&
      isValidMemexRefreshEventShape(data) &&
      data.payload.item_id === sidePanelMetadata.itemKey.projectItemId
    )
  }

  const [attrs] = useAliveChannel(
    aliveItemMessageRef,
    'message',
    detail => {
      if (isValidIssueEvent(detail.data) || isValidDraftEvent(detail.data)) {
        /**
         * Messages may have a waitFor attribute,
         * describing how long to wait for replication
         * lag before doing anything
         */
        setReloadMetadataTimeout(detail.data.wait ?? 0)(true)
      }
    },
    sidePanelMetadata.liveUpdateChannel,
  )

  const [paneAttrs] = useAliveChannel(alivePaneItemMessageRef, 'message', detail => {
    if (isValidMemexRefreshEventShape(detail.data)) {
      if (sidePanelState?.type !== SidePanelTypeParam.ISSUE) return
      if (
        !detail.data.payload ||
        (sidePanelState.item.memexItemId?.() !== detail.data.payload.memex_project_item_id &&
          sidePanelState.item.memexItemId?.() !== detail.data.payload.item_id)
      ) {
        return
      }
      /**
       * Messages may have a waitFor attribute,
       * describing how long to wait for replication
       * lag before doing anything
       */
      reloadPaneCancellable.current?.cancel()
      reloadPaneCancellable.current = setReloadPaneTimeout(detail.data.wait ?? 0)()
    }
  })

  useEffect(() => {
    /**
     * when the page becomes visible, we want to refresh the data
     * since we might have missed updates while it was not visible
     */
    if (isPageVisible && !isPageVisiblePrev) {
      reloadSidePanelMetadata(false)
      if (memex_side_panel_query) {
        invalidateSidePanelQueries()
      } else {
        if (memex_table_without_limits) {
          queryClient.invalidateQueries({queryKey: [sidePanelItemNotOnClientQueryKey]})
        } else {
          reloadPaneItem()
        }
      }
    }
  }, [
    isPageVisible,
    isPageVisiblePrev,
    reloadSidePanelMetadata,
    reloadPaneItem,
    memex_table_without_limits,
    memex_side_panel_query,
    invalidateSidePanelQueries,
    queryClient,
  ])

  const attrProps = isPageVisible ? attrs : undefined
  const paneAttrsProps = isPageVisible ? paneAttrs : undefined
  return (
    <>
      {sidePanelMetadata.liveUpdateChannel && (
        <span
          {...attrProps}
          ref={aliveItemMessageRef}
          hidden
          {...testIdProps('side-panel-item-live-update-listener')}
        />
      )}
      <span
        {...paneAttrsProps}
        ref={alivePaneItemMessageRef}
        hidden
        {...testIdProps('side-panel-pane-item-live-update-listener')}
      />
    </>
  )
})
