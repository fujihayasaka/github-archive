import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import type {
  DashboardSearchBarActionsFragment$data,
  SearchShortcutColor,
  SearchShortcutIcon,
} from '../components/dashboard/__generated__/DashboardSearchBarActionsFragment.graphql'

import {VALUES} from './values'

export const REVIEW_SECTION_IDS = {
  pullsAuthored: 'pullsAuthored',
  pullsReviewed: 'pullsReviewed',
  pullsReviewRequested: 'pullsReviewRequested',
  pullsMentioned: 'pullsMentioned',
}

export const RELAY_STORE_IDS = Object.values(VIEW_IDS)

type KnownViewBase = Partial<DashboardSearchBarActionsFragment$data> &
  Pick<DashboardSearchBarActionsFragment$data, 'id' | 'name' | 'icon' | 'query'> & {id: string}

/**
 * Sidebar shortcut that is a default view and maps to a query, e.g. the "Assigned to me" view
 */
type KnownQueryView = KnownViewBase & {url?: never; hidden?: boolean}

/**
 * Sidebar shortcut that maps to a new route, e.g. the "Pulls Assigned" view which maps to /pulls/assigned
 */
type KnownUrlView = KnownViewBase & {url: string; hidden?: boolean}

type KnownView = KnownQueryView | KnownUrlView

const knownViewDefaults = {
  color: VALUES.defaultViewColor as SearchShortcutColor,
  description: '',
  scopingRepository: null,
}

export const ASSIGNED_TO_ME_VIEW: KnownView = {
  id: VIEW_IDS.assignedToMe,
  name: 'Assigned to me',
  query: QUERIES.assignedToMe,
  icon: 'PEOPLE' as SearchShortcutIcon,
  hidden: false,
  ...knownViewDefaults,
}

export const REPOSITORY_VIEW: KnownView = {
  id: VIEW_IDS.repository,
  name: 'Issues',
  query: 'is:issue state:open',
  icon: 'PEOPLE' as SearchShortcutIcon,
  hidden: true,
  ...knownViewDefaults,
}

export const PULLS_ASSIGNED_TO_ME_VIEW: KnownView = {
  id: VIEW_IDS.pullsAssignedToMe,
  name: 'Assigned to me',
  query: QUERIES.pullsAssignedToMe,
  icon: 'PEOPLE' as SearchShortcutIcon,
  hidden: true,
  ...knownViewDefaults,
}

const MENTIONED_VIEW: KnownView = {
  id: VIEW_IDS.mentioned,
  name: 'Mentioned',
  query: QUERIES.mentioned,
  icon: 'MENTION' as SearchShortcutIcon,
  hidden: false,
  ...knownViewDefaults,
}

const CREATED_BY_ME_VIEW: KnownView = {
  id: VIEW_IDS.created,
  name: 'Created by me',
  query: QUERIES.createdByMe,
  icon: 'SMILEY' as SearchShortcutIcon,
  ...knownViewDefaults,
}

const RECENT_ACTIVITY_VIEW: KnownView = {
  id: VIEW_IDS.recent,
  name: 'Recent activity',
  query: QUERIES.recentActivity,
  icon: 'CLOCK' as SearchShortcutIcon,
  ...knownViewDefaults,
}

export const EMPTY_VIEW: KnownView = {
  id: VIEW_IDS.empty,
  name: 'Issues',
  query: 'is:issue state:open', // not used overwritten by the ?q= param
  icon: 'ISSUE_OPENED' as SearchShortcutIcon,
  hidden: true,
  ...knownViewDefaults,
}

export const NEW_VIEW: KnownView = {
  id: VIEW_IDS.new,
  name: 'New',
  query: 'is:issue state:open',
  icon: 'ISSUE_OPENED' as SearchShortcutIcon,
  hidden: true,
  ...knownViewDefaults,
}

export const CUSTOM_VIEWS = ['created_by', 'assigned', 'mentioned']
export const CUSTOM_VIEW = {
  defaultQuery: 'is:issue state:open',
  query: (customViewParams: {
    author?: string
    assignee?: string
    mentioned?: string
    createdByApp?: boolean
    label?: string
  }) => {
    if (customViewParams.author) {
      if (customViewParams.createdByApp) {
        return `author:app/${customViewParams.author}`
      }
      return `author:${customViewParams.author}`
    }
    if (customViewParams.assignee) {
      return `assignee:${customViewParams.assignee}`
    }
    if (customViewParams.mentioned) {
      return `mentions:${customViewParams.mentioned}`
    }
    if (customViewParams.label) {
      return `label:${customViewParams.label}`
    }
  },
}

export const DEFAULT_QUERY = 'is:issue'

/**
 * This is a list of all the views that are available as default views in the sidebar. This list changes based on feature
 * states, so useKnownViews hook (updates list based on FF state) is the preferred way to get this data.
 */
export const KNOWN_VIEWS: KnownView[] = [
  ASSIGNED_TO_ME_VIEW,
  CREATED_BY_ME_VIEW,
  MENTIONED_VIEW,
  RECENT_ACTIVITY_VIEW,
  REPOSITORY_VIEW,
]

export const SAVED_VIEW_GRAPHQL_ID_PREFIX = 'SSC'
