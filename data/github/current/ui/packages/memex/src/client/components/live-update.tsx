import {noop} from '@github-ui/noop'
import {PercentageCircle} from '@github-ui/percentage-circle'
import {testIdProps} from '@github-ui/test-id-props'
import {memo, useCallback, useEffect, useRef} from 'react'

import {cancelGetAllMemexData} from '../api/memex/api-get-all-memex-data'
import {
  isValidBulkCopyEventShape,
  isValidBulkUpdateCompleteEvent,
  isValidBulkUpdateProgressEvent,
  isValidMemexRefreshEventShape,
  isValidPaginatedRefreshEvent,
  isValidProjectMigrationEventShape,
  isValidRefreshEventType,
} from '../helpers/alive'
import {getInitialState} from '../helpers/initial-state'
import {useSetTimeout, useTimeout} from '../hooks/common/timeouts/use-timeout'
import {usePreviousValue} from '../hooks/common/use-previous-value'
import {useAliveChannel} from '../hooks/use-alive-channel'
import {useEnabledFeatures} from '../hooks/use-enabled-features'
import {usePageVisibility} from '../hooks/use-page-visibility'
import {BulkUpdateProgressSingleton} from '../state-providers/column-values/bulk-update-progress'
import {useHandleDataRefresh} from '../state-providers/data-refresh/use-handle-data-refresh'
import {useHandlePaginatedDataRefresh} from '../state-providers/data-refresh/use-handle-paginated-data-refresh'
import {useSingleDataRefresh} from '../state-providers/data-refresh/use-single-data-refresh'
import {useProcessProjectMigrationState} from '../state-providers/project-migration/use-process-project-migration-state'
import {BulkCopyResources, BulkUpdateResources} from '../strings'
import useToasts, {type AddToastProps, DEFAULT_TOAST_TIMEOUT, ToastType} from './toasts/use-toasts'

/** Delay in milliseconds before we show a toast notifying the user of the outcome of their bulk copy operation. */
const BULK_COPY_RESULT_TOAST_DELAY = 2000
/** Delay in milliseconds before we show a toast notifying the user of the outcome of their bulk update operation. */
const BULK_UPDATE_RESULT_TOAST_DELAY = 500

export const LiveUpdate = memo(function LiveUpdate() {
  const {
    addToast,
    updatePersistedToast: updatePersistedToastInternal,
    clearPersistedToast: clearPersistedToastInternal,
  } = useToasts()
  const addToastAfterDelay = useSetTimeout(addToast)
  const updatePersistedToast = useSetTimeout(updatePersistedToastInternal)
  const clearPersistedToast = useTimeout(clearPersistedToastInternal, DEFAULT_TOAST_TIMEOUT)
  const aliveMessageRef = useRef<HTMLSpanElement | null>(null)
  const handleDataRefresh = useHandleDataRefresh()
  const handleSingleMemexUpdate = useSingleDataRefresh()
  const setDataRefreshTimeout = useSetTimeout(handleDataRefresh)
  const {memex_table_without_limits, memex_new_bulk_update_ux} = useEnabledFeatures()

  const doSingleRefreshWithToast = useCallback(
    async (addToastProps: AddToastProps) => {
      await handleSingleMemexUpdate()
      addToastAfterDelay(BULK_COPY_RESULT_TOAST_DELAY)(addToastProps)
    },
    [handleSingleMemexUpdate, addToastAfterDelay],
  )
  // Disable this rule to keep paginated behind a FF (FFs are static for the lifetime of the component)
  const handlePaginatedDataRefresh = memex_table_without_limits
    ? // eslint-disable-next-line react-compiler/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useHandlePaginatedDataRefresh().handleRefresh
    : noop
  const isPageVisible = usePageVisibility()
  const isPageVisiblePrev = usePreviousValue(isPageVisible)
  const {processProjectMigrationState, processProjectMigrationOnPageVisibility, isMigrationComplete} =
    useProcessProjectMigrationState()

  const [attrs] = useAliveChannel(aliveMessageRef, 'message', detail => {
    if (isValidProjectMigrationEventShape(detail.data)) {
      processProjectMigrationState(detail.data.project_migration)
      setDataRefreshTimeout(detail.data.wait ?? 0)()
      return
    }

    if (isValidBulkUpdateProgressEvent(detail.data) && memex_table_without_limits && memex_new_bulk_update_ux) {
      const {loggedInUser} = getInitialState()
      const {percentage, actor, requestId} = detail.data
      const notifyUser = actor.id === loggedInUser?.id
      const completion = BulkUpdateProgressSingleton.progress(requestId, percentage)
      const updateProgress = notifyUser && completion

      if (updateProgress) {
        updatePersistedToast(0)({
          type: ToastType.default,
          message: BulkUpdateResources.progressMessage(completion),
          icon: () => <PercentageCircle radius={8} progress={completion / 100.0} />,
        })
      }
    }

    if (isValidBulkUpdateCompleteEvent(detail.data) && !(memex_table_without_limits && memex_new_bulk_update_ux)) {
      const {loggedInUser} = getInitialState()
      const {bulkUpdateSuccess, actor, bulkUpdateErrors, invalidateQueryCache} = detail.data

      const toastProps = {
        type: bulkUpdateSuccess ? ToastType.success : ToastType.error,
        message: bulkUpdateSuccess
          ? BulkUpdateResources.successMessage
          : BulkUpdateResources.refreshPageMessage(bulkUpdateErrors?.length || 0),
      }

      const notifyUser = actor.id === loggedInUser?.id

      if (invalidateQueryCache && notifyUser) {
        handlePaginatedDataRefresh()
        // Wait an approximate amount of time for the paginated data to refresh before showing the toast.
        addToastAfterDelay(BULK_UPDATE_RESULT_TOAST_DELAY)(toastProps)
      } else if (invalidateQueryCache) {
        handlePaginatedDataRefresh()
      } else if (notifyUser) {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast(toastProps)
      }
    }

    if (isValidBulkUpdateCompleteEvent(detail.data) && memex_table_without_limits && memex_new_bulk_update_ux) {
      const {loggedInUser} = getInitialState()
      const {bulkUpdateSuccess: success, actor, bulkUpdateErrors: errors, invalidateQueryCache, requestId} = detail.data
      const notifyUser = actor.id === loggedInUser?.id
      const notificationDelay = invalidateQueryCache ? BULK_UPDATE_RESULT_TOAST_DELAY : 0
      const showCompletionMessage =
        notifyUser && BulkUpdateProgressSingleton.complete(requestId, notificationDelay, () => clearPersistedToast())

      if (invalidateQueryCache) {
        handlePaginatedDataRefresh()
      }

      if (showCompletionMessage) {
        updatePersistedToast(notificationDelay)({
          type: success ? ToastType.success : ToastType.error,
          message: success
            ? BulkUpdateResources.successMessage
            : BulkUpdateResources.refreshPageMessage(errors?.length || 0),
        })
      }
    }

    if (isValidMemexRefreshEventShape(detail.data)) {
      const {type} = detail.data

      if (isValidRefreshEventType(type)) {
        /**
         * Messages may have a waitFor attribute,
         * describing how long to wait for replication
         * lag before doing anything
         */
        setDataRefreshTimeout(detail.data.wait ?? 0)()
      }
    } else if (isValidPaginatedRefreshEvent(detail.data)) {
      handlePaginatedDataRefresh(detail.data.timestamp, detail.data.request_id)
    }

    if (isValidBulkCopyEventShape(detail.data)) {
      const {loggedInUser} = getInitialState()
      const {bulkCopySuccess, actor} = detail.data
      if (actor.id === loggedInUser?.id) {
        doSingleRefreshWithToast({
          type: bulkCopySuccess ? ToastType.success : ToastType.error,
          message: bulkCopySuccess ? BulkCopyResources.successMessage : BulkCopyResources.failureMessage,
        })
      }
    }
  })

  useEffect(() => {
    if (isPageVisible) {
      processProjectMigrationOnPageVisibility()
    }

    /**
     * when the page becomes visible, we want to refresh the data
     * since we might have missed updates while it was not visible
     */
    if (isPageVisible && !isPageVisiblePrev) {
      // Refresh item data (noop when MWL is disabled)
      handlePaginatedDataRefresh()
      // Refresh project data (excludes items when MWL is enabled)
      handleDataRefresh()
    }
  }, [
    isPageVisible,
    isPageVisiblePrev,
    handleDataRefresh,
    processProjectMigrationOnPageVisibility,
    isMigrationComplete,
    handlePaginatedDataRefresh,
  ])

  useEffect(() => {
    /**
     * When we unmount, we want to cancel any pending requests
     */
    return () => {
      cancelGetAllMemexData()
    }
  }, [])

  const props = isPageVisible ? attrs : undefined
  return <span {...props} ref={aliveMessageRef} hidden {...testIdProps('live-update-listener')} />
})
