// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import type {TimelineItem} from '../components/timeline/IssueTimeline'

export const checkTimelineItems = (timelineItems: TimelineItem[], issueId: string) => {
  checkOrderByCreationDate(timelineItems, issueId)
}

const checkOrderByCreationDate = (timelineItems: TimelineItem[], issueId: string) => {
  let previousTimestamp = 0
  for (let i = 0; i < timelineItems.length; i++) {
    const item = timelineItems[i]
    if (item && item.type === 'event') {
      if (item.item?.createdAt) {
        const timestamp = new Date(item.item.createdAt).getTime()
        if (timestamp < previousTimestamp) {
          const errorMessage = `Found incorrect timeline items order at item number ${i} for issue ${issueId}`
          reportError(errorMessage)
          // eslint-disable-next-line no-console
          console.warn(errorMessage)
        }
        previousTimestamp = timestamp
      }
    }
  }
}
