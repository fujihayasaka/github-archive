import {Flash} from '@primer/react'
import {MESSAGES} from '../../constants/messages'

/**
 * A flash wrapper to be used in the timeline to inform the user of an existing issue transfer process.
 *
 * Parity item for IssueTimeline as part of the issues_react_new_timeline FF work
 * https://github.com/github/github/blob/c652fec1e847fde98ea2edbbe2fe5662821d95a6/ui/packages/issue-viewer/components/IssueTimeline.tsx#L338
 */
export const TimelineTransferringFlash = () => (
  <Flash
    aria-live="polite"
    variant="warning"
    sx={{
      mt: 3,
    }}
  >
    {MESSAGES.issueTimelineInTransfer}
  </Flash>
)
