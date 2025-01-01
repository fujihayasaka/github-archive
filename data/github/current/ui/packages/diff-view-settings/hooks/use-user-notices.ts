import {isLoggedIn} from '@github-ui/client-env'
import {dismissUserNoticePath} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useCallback} from 'react'

import type {CommitNotices, UserNotice} from '../types'

type UserNoticeRoutePayload = {
  userNotices: Array<UserNotice<CommitNotices>>
}

export function useUserNotices() {
  const payload = useRoutePayload<UserNoticeRoutePayload>()
  if (!payload) return []
  const notices = payload.userNotices ?? []

  return notices.filter(notice => !notice.dismissed)
}

export function useIsNoticeDismissed(notice: CommitNotices) {
  const activeNotices = useUserNotices()

  return activeNotices.filter(activeNotice => activeNotice.name === notice).length === 0
}

export function useDismissNotice(notice: CommitNotices) {
  const isNoticedDimissed = useIsNoticeDismissed(notice)

  const dismissNotice = useCallback(() => {
    // Don't dismiss the notice if the user is not logged in or the notice is already dismissed
    if (!isLoggedIn() || isNoticedDimissed) return

    verifiedFetch(dismissUserNoticePath({noticeName: notice}), {method: 'POST'})
  }, [isNoticedDimissed, notice])

  return {dismissNotice}
}
