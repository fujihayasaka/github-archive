import type {QUERY_FIELDS} from '@github-ui/query-builder/constants/queries'
import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {ROUTE_SUFFIXES} from './constants/route-suffixes'
import {VIEW_IDS} from './constants/view-constants'

export const issuesAtRepoIndexUrl = new RegExp(
  '^\\/([a-zA-Z0-9]+(-[a-zA-Z0-9]+|-)*)\\/(([\\-_\\.a-zA-Z0-9])*)\\/issues',
)
export const issuesAtLabelShowUrl = new RegExp(
  '^\\/([a-zA-Z0-9]+(-[a-zA-Z0-9]+|-)*)\\/(([\\-_\\.a-zA-Z0-9])*)\\/labels\\/([\\-_\\.a-zA-Z0-9]+)',
)
export const issuesAtMilestoneShowUrl = new RegExp(
  '^\\/([a-zA-Z0-9]+(-[a-zA-Z0-9]+|-)*)\\/(([\\-_\\.a-zA-Z0-9])*)\\/milestone\\/([0-9]+)',
)

export const searchUrl = ({viewId, query}: {viewId?: string; query?: string}) => {
  let newQuery = ''

  if (viewId !== VIEW_IDS.repository) {
    if (viewId && viewId !== VIEW_IDS.empty) {
      if (ROUTE_SUFFIXES[viewId]) {
        newQuery = `/${ROUTE_SUFFIXES[viewId]}`
      } else {
        newQuery = `/${viewId}`
      }
    } else {
      if (query === QUERIES.assignedToMe) {
        return `/issues/${ROUTE_SUFFIXES.assigned}`
      } else if (query === QUERIES.mentioned) {
        return `/issues/${ROUTE_SUFFIXES.mentioned}`
      } else if (query === QUERIES.createdByMe) {
        return `/issues/${ROUTE_SUFFIXES.createdByMe}`
      } else if (query === QUERIES.recentActivity) {
        return `/issues/${ROUTE_SUFFIXES.recentActivity}`
      }
    }
  }

  if (query !== undefined && query.trim() !== '') {
    newQuery = `${newQuery}?q=${encodeURIComponent(query)}`
  }

  if (viewId === VIEW_IDS.repository) {
    // this is when hyperlist is running at the repository level
    const path = ssrSafeLocation?.pathname
    let match = path.match(issuesAtRepoIndexUrl)

    if (match) {
      return path + newQuery
    }
    match = path.match(issuesAtLabelShowUrl) || path.match(issuesAtMilestoneShowUrl)
    if (match) {
      return `/${match[1]}/${match[3]}/issues${newQuery}`
    }
  }

  return `/issues${newQuery}`
}

// Removes all instances of the given field from the query, then adds the field with the new value
export function replaceInQuery(query: string, field: keyof typeof QUERY_FIELDS, value: string) {
  if (!query) {
    return undefined
  }
  const regex = new RegExp(`(?:^|\\s)${field}:(?:\\"[^\\"]*\\"|\\S+)`, 'g')
  const newQuery = query.replaceAll(regex, '').replace(/^\s+/, '')
  const newValue = value.indexOf(' ') > -1 ? `"${value}"` : value

  return `${newQuery.trim()} ${field}:${newValue}`
}
