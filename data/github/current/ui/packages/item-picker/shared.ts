import {CircleSlashIcon} from '@primer/octicons-react'

import {ERRORS} from './constants/errors'

import type {RepositoryVisibility} from './components/__generated__/RepositoryPickerRepository.graphql'

type ItemGroupVariant = 'subtle' | 'filled'

export type ItemGroup = {
  groupId: string
  header?: {
    title: string
    variant?: ItemGroupVariant
  }
}

export const noMatchesItem = {
  leadingVisual: CircleSlashIcon,
  text: ERRORS.noMatches,
  disabled: true,
  selected: undefined, // hide checkbox
  key: 'no-matches',
  id: 'no-matches',
}

export const noResultsItem = {
  leadingVisual: CircleSlashIcon,
  text: ERRORS.noResults,
  disabled: true,
  selected: undefined, // hide checkbox
  key: 'no-results',
  id: 'no-results',
}

export const maybeIssueUrl = (url: string): boolean => {
  try {
    // eslint-disable-next-line no-restricted-syntax
    new URL(url)
  } catch {
    return false
  }

  return new RegExp(/^.+\/issues\/\d+$/).test(url)
}

// Attempt to use the `org` parameter to filter the results if we have a `/` present in the query
// This is to be used with the `search` graphQL endpoint for type `Repository` only.
export function getRepositorySearchQuery(
  queryString: string,
  organization?: string,
  excludeRepo?: string,
  includeForks?: boolean,
  repositoryVisibility?: RepositoryVisibility,
): string {
  const orgIndexSplit = queryString.indexOf('/')

  let query = 'in:name archived:false'
  if (excludeRepo) {
    query = `${query} -repo:${excludeRepo}`
  }

  if (includeForks) {
    query = `${query} fork:true`
  }

  if (repositoryVisibility && repositoryVisibility !== 'PUBLIC') {
    // If the repository visibility is public, we don't need to add it to the query.
    // If it is either internal or private, we need to exclude the public repositories from the query.
    query = `${query} -visibility:public`
  }
  // if there is <owner>/<repo> in the query, use that to filter the results
  if (orgIndexSplit > 0 && queryString.split('/').length === 2) {
    // Naively extract the org name and repo name from the query by assuming anything before the / is the org name
    const orgSearchName = queryString.split('/')[0]!
    const repoSearchName = queryString.split('/')[1]!
    return `${query} org:${orgSearchName} ${repoSearchName}`
  }

  // If there is an org name, use that to filter the results
  if (organization) {
    return `${query} org:${organization} ${queryString}`
  }

  // If there is no / in the query, or the org name is empty, just search for the repo name
  return `${query} ${queryString}`
}

// Generates a set of queries which scope to an owner, and prioritizes issues based on interaction
// The IssuePickerInternal orders the queried issues and is the source for this order of this priority
export const getIssueSearchQueries = (owner = '', query = '', repoNameWithOwner = '') => {
  const ownerPart = owner && `owner:${owner.trim()} `
  const repoPart = repoNameWithOwner && `repo:${repoNameWithOwner.trim()} `
  const queryPart = query && `${query.trim()}`

  // Although these queries are using the `... on Issue` type condition,
  // PR results are still inlcuded in the response in an empty object.
  // `is:issue` ensures that only issue nodes are returned.
  const issuePart = 'is:issue '
  const queryIsUrl = maybeIssueUrl(query)

  // By default, search within the issue title as it's the most relevant option.
  let inPart = 'in:title'

  // If the query is a number (123 or #123), then we should search for the issue by number as well.
  const maybeNumber = queryPart && queryPart.charAt(0) === '#' ? queryPart.slice(1) : queryPart
  if (maybeNumber && !isNaN(Number(maybeNumber))) {
    inPart += ' in:number'
  }

  const sharedQuery = `${ownerPart}${repoPart}${issuePart}${inPart}`

  return {
    commenters: `${sharedQuery} commenter:@me ${queryPart}`.trim(),
    mentions: `${sharedQuery} mentions:@me ${queryPart}`.trim(),
    assignee: `${sharedQuery} assignee:@me ${queryPart}`.trim(),
    author: `${sharedQuery} author:@me ${queryPart}`.trim(),
    other: `${sharedQuery} ${queryPart}`.trim(),
    resource: queryIsUrl ? encodeURI(query) : '',
    queryIsUrl,
  }
}

export type Unpacked<T> = T extends Array<infer U> ? U : T
