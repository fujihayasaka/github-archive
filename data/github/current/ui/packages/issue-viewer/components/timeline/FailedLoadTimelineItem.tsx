import {FallbackEvent} from '@github-ui/timeline-items/FallbackEvent'
import {TimelineRowBorder} from '@github-ui/timeline-items/TimelineRowBorder'

/**
 * A timeline item component that represents a failed load event.
 *
 * This component is a parity item for TimelineItems, created as part of the issues_react_new_timeline feature flag work.
 * https://github.com/github/github/blob/50680482a2fc6c0d2a13c36e34893433d205e986/ui/packages/issue-viewer/components/TimelineItems.tsx#L384
 */
export const FailedLoadTimelineItem = () => (
  <TimelineRowBorder addDivider item={{__id: `failed-timeline-item`}}>
    <FallbackEvent />
  </TimelineRowBorder>
)
