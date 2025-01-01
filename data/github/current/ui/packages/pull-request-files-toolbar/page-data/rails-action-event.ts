import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {ssrSafeDocument} from '@github-ui/ssr-utils'

const EVENT_NAME: string = 'rails-action-event'

const hasPullRequestFilesToolbarPartial = (): boolean =>
  !!ssrSafeDocument?.querySelector('#react-partial-pull-requests-files-toolbar')

export const sendUpdateViewedFilesEvent = () => {
  if (!hasPullRequestFilesToolbarPartial()) return

  const event = new CustomEvent(EVENT_NAME, {
    detail: PageData.viewedFilesCount,
  })

  ssrSafeDocument?.dispatchEvent(event)
}

export const sendUpdateThreadPreviewsEvent = () => {
  if (!hasPullRequestFilesToolbarPartial()) return

  const event = new CustomEvent(EVENT_NAME, {
    detail: PageData.threadPreviews,
  })

  ssrSafeDocument?.dispatchEvent(event)
}

export const sendUpdatePendingReviewEvent = () => {
  if (!hasPullRequestFilesToolbarPartial()) return

  const event = new CustomEvent(EVENT_NAME, {
    detail: PageData.pendingReview,
  })

  ssrSafeDocument?.dispatchEvent(event)
}
