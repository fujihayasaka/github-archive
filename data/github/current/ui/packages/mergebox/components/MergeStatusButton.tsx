import {testIdProps} from '@github-ui/test-id-props'
import {ClockIcon} from '@primer/octicons-react'
import {Box, Button} from '@primer/react'
import {memo, type RefObject, Suspense, useCallback, useRef, useState} from 'react'

import {MergeabilitySidesheet} from './MergeabilitySidesheet'
import {presentationForStatus, Status, mergeabilityStatus} from '../helpers/mergeability-status'
import {useMergeBoxPageData} from '../page-data/loaders/use-merge-box-page-data'
import {useMergeMethodContext} from '../contexts/MergeMethodContext'
import type {MergeBoxPageData} from '../page-data/payloads/merge-box'
import type {Channels} from '../hooks/use-mergeability-live-updates'

/**
 * Loads the merge-related data and provides a fallback state for the merge status button
 */
export const MergeStatusButtonWithSuspense = memo(function MergeStatusButtonWithSuspense({
  viewerLogin,
  helpUrl,
  channels,
}: {
  viewerLogin: string
  helpUrl: string
  channels: Channels
}) {
  const mergeStatusButtonRef = useRef<HTMLButtonElement>(null)
  const [mergeabilitySidesheetIsOpen, setMergeabilitySidesheetIsOpen] = useState(false)
  const toggleMergeabilitySidesheet = useCallback(
    (isOpen: boolean) => {
      setMergeabilitySidesheetIsOpen(isOpen)
    },
    [setMergeabilitySidesheetIsOpen],
  )

  const sidesheet = (
    <MergeabilitySidesheet
      helpUrl={helpUrl}
      mergeStatusButtonRef={mergeStatusButtonRef}
      mergeabilitySidesheetIsOpen={mergeabilitySidesheetIsOpen}
      toggleMergeabilitySidesheet={toggleMergeabilitySidesheet}
      viewerLogin={viewerLogin}
      channels={channels}
    />
  )

  const fallback = (
    <>
      <Button ref={mergeStatusButtonRef} leadingVisual={ClockIcon} onClick={() => toggleMergeabilitySidesheet(true)}>
        Status: Calculating mergeability…
      </Button>
      {sidesheet}
    </>
  )

  return (
    <Suspense fallback={fallback}>
      <MergeStatusButtonWrapper
        mergeStatusButtonRef={mergeStatusButtonRef}
        toggleMergeabilitySidesheet={toggleMergeabilitySidesheet}
      />
      {sidesheet}
    </Suspense>
  )
})

interface MergeStatusButtonCommonProps {
  mergeStatusButtonRef: RefObject<HTMLButtonElement> | null
  toggleMergeabilitySidesheet: (isOpen: boolean) => void
}

/**
 * A button that displays the merge status of a pull request.
 * Opens the mergeability sidesheet.
 */
function MergeStatusButtonWrapper({...rest}: MergeStatusButtonCommonProps) {
  const {mergeMethod} = useMergeMethodContext()
  const {data} = useMergeBoxPageData({mergeMethod, bypassRequirements: false})

  if (!data) return null

  return <MergeStatusButton pullRequest={data.pullRequest} mergeRequirements={data.mergeRequirements} {...rest} />
}

export type MergeStatusButtonData = MergeBoxPageData

export function MergeStatusButton({
  pullRequest,
  mergeRequirements,
  mergeStatusButtonRef,
  toggleMergeabilitySidesheet,
}: MergeStatusButtonData & MergeStatusButtonCommonProps) {
  if (!mergeStatusButtonRef) return null

  const status = mergeabilityStatus({pullRequest, mergeRequirements})
  // Don't render merge status button if failure is non-actionable (repo is not writeable, etc.)
  if (status === Status.NonactionableFailure) return null

  const presentation = presentationForStatus(status)
  const isPrimary = status === Status.Mergeable && pullRequest.viewerDidAuthor

  return (
    <Button
      ref={mergeStatusButtonRef}
      leadingVisual={presentation.icon}
      variant={isPrimary ? 'primary' : 'default'}
      {...testIdProps('merge-status-button')}
      sx={{
        color: isPrimary ? 'fg.primary' : 'fg.default',
        '[data-component="leadingVisual"]': {
          color: isPrimary ? 'fg.primary' : presentation.iconColor,
        },
      }}
      onClick={() => {
        toggleMergeabilitySidesheet?.(true)
      }}
    >
      <Box as="span" sx={{display: ['flex', 'flex', 'flex', 'none']}}>
        View status
      </Box>
      <Box as="span" sx={{gap: 1, display: ['none', 'none', 'none', 'flex']}}>
        {status !== Status.Mergeable && (
          <Box as="span" sx={{color: 'fg.muted', fontWeight: 'normal'}}>
            Status:{' '}
          </Box>
        )}
        {presentation.title}
      </Box>
    </Button>
  )
}
