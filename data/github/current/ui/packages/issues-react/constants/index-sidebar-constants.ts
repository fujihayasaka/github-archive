export const ISSUES_INDEX_DEFAULT_TITLE = 'Search'

export const ISSUES_INDEX_QUICK_FILTERS = [
  {
    name: 'Open Issues',
    icon: 'ISSUE_OPENED',
    query: 'is:issue state:open',
  },
  {
    name: 'Your Issues',
    icon: 'SMILEY',
    query: 'is:issue state:open author:@me',
  },
  {
    name: 'Assigned to You',
    icon: 'PERSON',
    query: 'is:issue state:open assignee:@me',
  },
  {
    name: 'Mentioning You',
    icon: 'MENTION',
    query: 'is:issue state:open mentions:@me',
  },
  {
    name: 'Recent Activity',
    icon: 'CLOCK',
    query: 'is:issue state:open involves:@me updated:>@today-1w',
  },
]
