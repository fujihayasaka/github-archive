import type {HeaderPageData} from '../page-data/payloads/header'
import {PullRequestHiddenCharactersBanner} from './banners/PullRequestHiddenCharactersBanner'
import {PullRequestAutomatedSecurityUpdateBanner} from './banners/PullRequestAutomatedSecurityUpdateBanner'
import {PullRequestPausedDependabotBanner} from './banners/PullRequestPausedDependabotBanner'

export function PullRequestBanners({bannersData, pullRequest, repository}: Omit<HeaderPageData, 'urls' | 'user'>) {
  return (
    <>
      {bannersData.banners.hiddenCharacterWarning.render && (
        <PullRequestHiddenCharactersBanner pullRequest={pullRequest} />
      )}
      {bannersData.banners.pausedDependabotUpdate.render && (
        <PullRequestPausedDependabotBanner repository={repository} />
      )}
      {bannersData.banners.dependabotAutomatedSecurityUpdates.render && pullRequest.state === 'open' && (
        <PullRequestAutomatedSecurityUpdateBanner
          dependabotUpdates={bannersData.banners.dependabotAutomatedSecurityUpdates}
          pullRequest={pullRequest}
        />
      )}
    </>
  )
}
