import useSafeState from '@github-ui/use-safe-state'
import {StopIcon} from '@primer/octicons-react'
import {Button, Flash, Link, Spinner, Text} from '@primer/react'
import {Dialog, Octicon} from '@primer/react/deprecated'

import {MergeBoxSectionHeader} from '../common/MergeBoxSectionHeader'
import type {MergeQueue, MergeQueueEntry} from '../../../types'
import {useRef} from 'react'
import {announce} from '@github-ui/aria-live'
import {useAnalytics} from '@github-ui/use-analytics'
import {useDequeuePullRequestMutation} from '../../../hooks/mutations/use-dequeue-pull-request-mutation'

type MergeButtonFocusProps = {
  focusPrimaryMergeButton: () => void
}

export type Props = {
  mergeQueue: MergeQueue
  mergeQueueEntry: MergeQueueEntry
  viewerCanAddAndRemoveFromMergeQueue: boolean
} & MergeButtonFocusProps

/**
 *
 * Displays queue position details and allows user to dequeue the pull request
 */
export function MergeQueueSection({
  mergeQueue,
  mergeQueueEntry,
  viewerCanAddAndRemoveFromMergeQueue,
  focusPrimaryMergeButton,
}: Props) {
  const mergePosition = mergeQueueEntry?.position
  const mergeQueueUrl = mergeQueue?.url

  const returnConfirmationRef = useRef<HTMLButtonElement>(null)
  const [isConfirmationDialogOpen, setIsConfirmationDialogOpen] = useSafeState(false)
  const [errorMessage, setErrorMessage] = useSafeState<string | null>(null)

  const {sendAnalyticsEvent} = useAnalytics()

  const {mutate: onRemoveFromQueue, isPending} = useDequeuePullRequestMutation({
    onError: (e: Error) => {
      setIsConfirmationDialogOpen(false)
      setErrorMessage(e.message)
      returnConfirmationRef.current?.focus()
      setTimeout(() => announce('Failed to remove pull request from the merge queue'), 1000)
    },
  })

  const handleDequeue = () => {
    if (isPending) return
    setErrorMessage(null)
    sendAnalyticsEvent(
      'merge_queue_section.dequeue_pull_request',
      'MERGEBOX_MERGE_QUEUE_SECTION_REMOVE_FROM_QUEUE_BUTTON',
    )

    onRemoveFromQueue(undefined, {
      onSuccess: () => {
        setIsConfirmationDialogOpen(false)
        setTimeout(() => announce('The pull request was successfully removed from the queue.'), 1000)
        focusPrimaryMergeButton()
      },
    })
  }

  const handleOpenConfirmation = () => {
    setErrorMessage(null)
    setIsConfirmationDialogOpen(true)
  }

  return (
    <>
      <Dialog
        aria-labelledby="remove-from-queue-dialog-title"
        isOpen={isConfirmationDialogOpen}
        returnFocusRef={returnConfirmationRef}
        onDismiss={() => setIsConfirmationDialogOpen(false)}
      >
        <Dialog.Header id="remove-from-queue-dialog-title">Remove from the queue?</Dialog.Header>
        <div className="p-3">
          <span>
            Removing this pull request from the queue could impact other pull requests in the queue. Are you sure?
          </span>
          <div className="d-flex flex-justify-end mt-3">
            <Button
              className="mr-1"
              inactive={isPending}
              onClick={() => {
                if (!isPending) {
                  setIsConfirmationDialogOpen(false)
                  returnConfirmationRef.current?.focus()
                }
              }}
            >
              Cancel
            </Button>
            <Button variant="danger" aria-disabled={isPending} inactive={isPending} onClick={handleDequeue}>
              <div className="d-flex flex-row flex-items-center">
                {isPending && <Spinner size="small" sx={{mr: 2}} />}
                {isPending ? 'Removing' : 'Remove'} from the queue
              </div>
            </Button>
          </div>
        </div>
      </Dialog>
      {errorMessage && (
        <Flash className="mx-3 my-2" variant="danger">
          <Octicon className="mr-2" icon={StopIcon} />
          {errorMessage}
        </Flash>
      )}
      <MergeBoxSectionHeader
        title="Queued to merge..."
        rightSideContent={
          <>
            {viewerCanAddAndRemoveFromMergeQueue && !mergeQueueEntry?.isLocked && (
              <Button ref={returnConfirmationRef} onClick={handleOpenConfirmation}>
                Remove from queue
              </Button>
            )}
          </>
        }
      >
        <MergeQueuePositionText
          position={mergePosition}
          resourcePath={mergeQueueUrl}
          entryIsLocked={mergeQueueEntry?.isLocked}
        />
      </MergeBoxSectionHeader>
    </>
  )
}

function MergeQueuePositionText({
  position,
  resourcePath,
  entryIsLocked,
}: {
  position?: number
  resourcePath?: string
  entryIsLocked?: boolean
}) {
  if (!position || !resourcePath) return <></>
  const pullsBeforeInQueue = position - 1

  let text: string = ''
  if (entryIsLocked) {
    text = `This pull request is locked for deployment by the`
  } else if (pullsBeforeInQueue === 0) {
    text = 'This pull request is next up in the'
  } else if (pullsBeforeInQueue === 1) {
    text = `There is ${pullsBeforeInQueue} pull request ahead of this one in the`
  } else {
    text = `There are ${pullsBeforeInQueue} pull requests ahead of this one in the`
  }

  return (
    <>
      <Text sx={{color: 'fg.muted'}}>{text}</Text>{' '}
      <Link inline href={resourcePath}>
        merge queue
      </Link>
      .
    </>
  )
}
