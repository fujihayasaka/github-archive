import {ClockIcon, IssueOpenedIcon, MentionIcon, PersonIcon, SmileyIcon} from '@primer/octicons-react'

export const ISSUES_INDEX_DEFAULT_TITLE = 'Search'

export const ISSUES_INDEX_QUICK_FILTERS = [
  {
    name: 'Open Issues',
    icon: IssueOpenedIcon,
    query: 'is:issue state:open',
  },
  {
    name: 'Your Issues',
    icon: SmileyIcon,
    query: 'is:issue state:open author:@me',
  },
  {
    name: 'Assigned to You',
    icon: PersonIcon,
    query: 'is:issue state:open assignee:@me',
  },
  {
    name: 'Mentioning You',
    icon: MentionIcon,
    query: 'is:issue state:open mentions:@me',
  },
  {
    name: 'Recent Activity',
    icon: ClockIcon,
    query: 'is:issue state:open involves:@me updated:>@today-1w',
  },
]
