import {useCommentEditsContext} from '@github-ui/commenting/CommentEditsContext'
import {issueUrl} from '@github-ui/issue-viewer/Urls'
import {prefetchIssue} from '@github-ui/issue-viewer/IssueViewerLoader'
import {useInputElementActiveContext} from '@github-ui/issue-viewer/InputElementActiveContext'

import type {QUERY_FIELDS} from '@github-ui/list-view-items-issues-prs/Queries'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
import type {NavigateOptionsWithPreventAutofocus} from '@github-ui/use-navigate'
import {useNavigate} from '@github-ui/use-navigate'
import {useCallback, useRef} from 'react'
import {useRelayEnvironment} from 'react-relay/hooks'
import type {NavigateOptions, To} from 'react-router-dom'

import {MESSAGES} from '../constants/messages'
import {EMPTY_VIEW} from '../constants/view-constants'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {useQueryContext} from '../contexts/QueryContext'
import type {AppPayload} from '../types/app-payload'
import {getUrlWithHash, isUrlInRepoIssuesContext, issueRegexpWithoutDomain} from '../utils/urls'
import {searchUrl, issuesAtRepoIndexUrl, replaceInQuery} from '@github-ui/issue-url-helper'
import {startSoftNav} from '@github-ui/soft-nav/state'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

// regexp to extract the owner, repo and issue number from a url
const issueRegexp =
  /https?:\/\/(?<hostname>github\.(com|localhost|localhost:\d+))\/(?<owner>.*)\/(?<repo>.*)\/issues\/(?<number>\d+)/

type NavigateToViewOptions = {
  viewId: string
  canEditView: boolean
  teamId?: string | undefined
  isEditing?: boolean
  navigateOptions?: NavigateOptions | undefined
  isNewView?: boolean
}

type NavigateToSavedViewOptions = {
  (viewId: string, options?: Pick<NavigateToViewOptions, 'isEditing' | 'isNewView'>): void
}

export const useAppNavigate = () => {
  const {setCanEditView, activeSearchQuery, setIsEditing, setIsNewView} = useQueryContext()
  const {scoped_repository, multi_tenant} = useAppPayload<AppPayload>()

  const {isAnyInputElementActive} = useInputElementActiveContext()
  const {isCommentEditActive, cancelAllCommentEdits} = useCommentEditsContext()
  const pendingNavigationUrl = useRef<string | null>(null)
  const navigate = useNavigate()
  const environment = useRelayEnvironment()
  const {issues_react_force_turbo_nav} = useFeatureFlags()

  const navigateToUrl = useCallback(
    async (to: To, options?: NavigateOptionsWithPreventAutofocus, resetScroll?: boolean) => {
      if (isAnyInputElementActive) {
        return
      }

      if (isCommentEditActive()) {
        const confirmed = confirm(MESSAGES.confirmLeave)
        if (!confirmed) {
          return
        }
        cancelAllCommentEdits()
      }

      const fullUrl = new URL(to.toString(), ssrSafeLocation.origin)
      const url = fullUrl.pathname

      const matchIssueViewerRoute = url.match(issueRegexpWithoutDomain)
      const matchIssuesIndexRoute = url.match(issuesAtRepoIndexUrl)
      if (matchIssueViewerRoute && matchIssueViewerRoute.groups) {
        const {owner: _owner, repo: _repo, number: _number} = matchIssueViewerRoute.groups
        if (_owner && _repo && _number) {
          const issueNumber = parseInt(_number)
          pendingNavigationUrl.current = url
          startSoftNav('react')

          await prefetchIssue(environment, _owner, _repo, issueNumber)

          // Ensure we are navigating to the last clicked URL, and also we haven't already navigated.
          if (pendingNavigationUrl.current === url && url !== ssrSafeWindow?.location.pathname) {
            pendingNavigationUrl.current = null
            if (resetScroll) {
              window.scrollTo(0, 0)
            }
            navigate(to, options)
          }
        }
      } else if (matchIssuesIndexRoute && multi_tenant && issues_react_force_turbo_nav) {
        // workaround for nav not working properly in issues index for proxima only
        // see https://github.com/github/proxima/issues/4084
        // guarded by both feature flag and multi_tenant check
        ;(async () => {
          // eslint-disable-next-line import/no-extraneous-dependencies
          const {softNavigate: turboSoftNavigate} = await import('@github-ui/soft-navigate')
          turboSoftNavigate(fullUrl)
        })()
      } else {
        if (resetScroll) {
          window.scrollTo(0, 0)
        }
        navigate(to, options)
      }
    },
    [
      cancelAllCommentEdits,
      environment,
      isAnyInputElementActive,
      isCommentEditActive,
      issues_react_force_turbo_nav,
      multi_tenant,
      navigate,
    ],
  )

  const onIssueHrefLinkClick = useCallback(
    (event: MouseEvent) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.metaKey || event.shiftKey || event.ctrlKey || event.button === 1) return
      if (!(event.target instanceof HTMLElement)) return

      let href = ''
      if (event.currentTarget instanceof HTMLAnchorElement) {
        href = event.currentTarget.href
      } else if (event.target instanceof HTMLAnchorElement) {
        href = event.target.href
      } else {
        href = event.target.closest('a')?.href ?? ''
      }

      if (href?.length > 0) {
        const match = href.match(issueRegexp)
        if (match && match.groups) {
          const {hostname: _hostname, owner: _owner, repo: _repo, number: _number} = match.groups
          if (_hostname !== window.location.hostname) return

          if (_owner && _repo && _number) {
            event.preventDefault()

            const issueHref = issueUrl({owner: _owner, repo: _repo, number: parseInt(_number)})
            const to = getUrlWithHash(issueHref, href)
            if (
              isUrlInRepoIssuesContext(window.location.href, _owner, _repo) &&
              !window.location.href.includes(issueHref)
            ) {
              // we only want to navigate to other issue, not to locations on the page
              event.preventDefault()
              navigateToUrl(to)
            } else {
              window.location.assign(to)
            }
          }
        }
      }
    },
    [navigateToUrl],
  )

  const getQueryFieldUrl = useCallback(
    (field: keyof typeof QUERY_FIELDS, value: string) => {
      return searchUrl({
        viewId: scoped_repository ? VIEW_IDS.repository : undefined,
        query: replaceInQuery(activeSearchQuery, field, value),
      })
    },
    [activeSearchQuery, scoped_repository],
  )

  const navigateToView = useCallback(
    ({
      viewId,
      canEditView,
      isEditing = false,
      navigateOptions = undefined,
      isNewView = false,
    }: NavigateToViewOptions) => {
      navigate(searchUrl({viewId}), navigateOptions)
      setCanEditView(canEditView)
      setIsEditing(isEditing)
      setIsNewView(isNewView)
    },

    [navigate, setCanEditView, setIsEditing, setIsNewView],
  )

  const navigateToSavedView: NavigateToSavedViewOptions = useCallback(
    (viewId, options = {}) => {
      const {isEditing = true, isNewView = false} = options
      navigateToView({viewId, canEditView: true, isEditing, isNewView})
    },
    [navigateToView],
  )

  const navigateToSearch = useCallback(
    (viewId: string | undefined, newQuery: string | undefined) => {
      navigate(searchUrl({viewId, query: newQuery}))
    },
    [navigate],
  )

  const navigateToRoot = useCallback(
    (viewId: string | undefined, viewQuery?: string | undefined) => {
      if (scoped_repository) {
        navigateToUrl(`/${scoped_repository.owner}/${scoped_repository.name}/issues`)
      } else if (viewId === EMPTY_VIEW.id) {
        navigateToSearch(undefined, activeSearchQuery)
      } else {
        // if the query is not the query for the active view, do not pass the view id as param
        // so that we navigate from root /?q=... instead of /assigned?q=... for example
        const navQuery = viewQuery !== activeSearchQuery ? activeSearchQuery : undefined
        navigateToSearch(navQuery ? undefined : viewId, navQuery)
      }
    },
    [activeSearchQuery, navigateToSearch, navigateToUrl, scoped_repository],
  )

  return {
    onIssueHrefLinkClick,
    navigateToUrl,
    navigateToView,
    navigateToSavedView,
    navigateToSearch,
    navigateToRoot,
    getQueryFieldUrl,
  }
}
