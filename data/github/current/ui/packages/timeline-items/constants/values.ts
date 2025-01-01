export const VALUES = {
  ghostUserLogin: 'ghost',
  lockedReasonStrings: {
    OFF_TOPIC: 'off topic',
    RESOLVED: 'resolved',
    SPAM: 'spam',
    TOO_HEATED: 'too heated',
  },
  labelQuery: (name: string) => `state:open label:"${name}"`,
  timeline: {
    majorEventTypes: [
      'IssueComment',
      'ClosedEvent',
      'ReopenedEvent',
      'CrossReferencedEvent',
      'ReferencedEvent',
      'PullRequestReview',
    ],
    borderedMajorEventTypes: ['IssueComment'],
    badgeSize: 18,
    pageSize: 150,
    maxPreloadCount: 150,
    /** Data attribute used to identify all timeline item elements, used for a11y focusing behaviors */
    dataTimelineEventId: 'data-timeline-event-id',
  },
  commitBadgeHelpUrl:
    'https://docs.github.com/github/authenticating-to-github/displaying-verification-statuses-for-all-of-your-commits',
  closingViaCommitMessageUrl: 'https://docs.github.com/articles/closing-issues-via-commit-messages',
}
