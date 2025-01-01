import {Banner} from '@primer/react/experimental'

import type {FilesRoutePayload, PageLimits} from '../page-data/payloads/files'
import type {NavigationUrls} from '../types/navigation-urls-types'
import {Link} from '@primer/react'
import {toggleGenericFeaturePath} from '@github-ui/paths'
import {verifiedFetch} from '@github-ui/verified-fetch'

/**
 * Props for the PageLimitsBanner component
 */
export type PageLimitsBannerProps = {
  /**
   * Object containing information about page limits and whether they are exceeded
   * Includes limits for files, review threads, and annotations
   */
  pageLimits: PageLimits
  /**
   * Repository information including owner and name
   */
  repository: FilesRoutePayload['repository']
  /**
   * Navigation URLs for the pull request, used for the "switch back" link
   */
  urls: NavigationUrls
}

/**
 * Displays a warning banner when page limits are exceeded in a pull request.
 *
 * Shows a banner when files,
 *  review threads, or annotations limits are exceeded as defined in pageLimits
 *
 * The banner includes a link to switch back to the classic pull request page
 * to view all content without limits.
 */
export function PageLimitsBanner({pageLimits, repository, urls}: PageLimitsBannerProps) {
  const pageLimitsExceeded =
    pageLimits.filesLimitExceeded || pageLimits.reviewThreadsLimitExceeded || pageLimits.annotationsLimitExceeded

  const limitExceededMessage = () => {
    const messagePrefix = 'Only the first '
    const messagePostfix = ' are currently being shown.'

    const exceededLimitCounts = []
    if (pageLimits.filesLimitExceeded) {
      exceededLimitCounts.push(`${pageLimits.filesLimit} files`)
    }
    if (pageLimits.reviewThreadsLimitExceeded) {
      exceededLimitCounts.push(`${pageLimits.reviewThreadsLimit} comments`)
    }
    if (pageLimits.annotationsLimitExceeded) {
      exceededLimitCounts.push(`${pageLimits.annotationsLimit} alerts`)
    }

    let formattedLimits = ''
    if (exceededLimitCounts.length === 1) {
      formattedLimits = `${exceededLimitCounts[0]}`
    } else if (exceededLimitCounts.length === 2) {
      formattedLimits = `${exceededLimitCounts[0]} and ${exceededLimitCounts[1]}`
    } else if (exceededLimitCounts.length === 3) {
      formattedLimits = `${exceededLimitCounts[0]}, ${exceededLimitCounts[1]}, and ${exceededLimitCounts[2]}`
    }

    return messagePrefix + formattedLimits + messagePostfix
  }

  async function handleFeaturePreviewToggle() {
    const formData = new FormData()
    formData.append('feature_name', 'prx_files')

    await verifiedFetch(toggleGenericFeaturePath({repo: repository}), {
      body: formData,
      method: 'POST',
    })
  }

  const warningDescription = (
    <>
      {limitExceededMessage()} To see more,{' '}
      <Link inline href={`${urls.files}?new_files_changed=false`} onClick={handleFeaturePreviewToggle} rel="noreferrer">
        switch back
      </Link>{' '}
      to the classic page.
    </>
  )

  if (!pageLimitsExceeded) return null

  return (
    <Banner
      aria-label="Warning"
      title="Warning"
      variant="warning"
      hideTitle
      description={warningDescription}
      className="mb-3"
    />
  )
}
