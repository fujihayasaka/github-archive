import {
  graphql,
  useFragment,
  usePreloadedQuery,
  useQueryLoader,
  useRelayEnvironment,
  type PreloadedQuery,
} from 'react-relay'
import type {
  FirstTimeContributionBanner$data,
  FirstTimeContributionBanner$key,
} from './__generated__/FirstTimeContributionBanner.graphql'
import {FirstTimeContributionBannerDisplay} from './FirstTimeContributionBannerDisplay'
import {Suspense, useCallback, useEffect, useMemo} from 'react'
import {dismissRepoFirstTimeContributionBannerMutation} from '../../mutations/dismiss-first-time-contribution-banner-for-repo-mutation'
import {dismissFirstTimeContributionBannerMutation} from '../../mutations/dismiss-first-time-contribution-banner-mutation'
import type {FirstTimeContributionBannerContributingGuidelinesQuery} from './__generated__/FirstTimeContributionBannerContributingGuidelinesQuery.graphql'

// Fetching the contributing guidelines link for the repository
// can be slow since it's using gitrpc, so we fecth it in a secondary query
export const FirstTimeContributionBannerContributingGuidelinesGraphqlQuery = graphql`
  query FirstTimeContributionBannerContributingGuidelinesQuery($node: ID!) {
    node(id: $node) {
      ... on Repository {
        contributingGuidelines {
          firstTimeContributionLink
        }
      }
    }
  }
`

export type FirstTimeContributionBannerProps = {
  repository: FirstTimeContributionBanner$key
}

export const FirstTimeContributionBanner = ({repository}: FirstTimeContributionBannerProps) => {
  const environment = useRelayEnvironment()
  const [bannerLazyDataRef, loadBannerLazyData] =
    useQueryLoader<FirstTimeContributionBannerContributingGuidelinesQuery>(
      FirstTimeContributionBannerContributingGuidelinesGraphqlQuery,
    )
  const data = useFragment(
    graphql`
      fragment FirstTimeContributionBanner on Repository {
        id
        showFirstTimeContributorBanner(isPullRequests: false)
        nameWithOwner
        communityProfile {
          goodFirstIssueIssuesCount
        }
        url
      }
    `,
    repository,
  )

  const dismissForThisRepo = useCallback(() => {
    dismissRepoFirstTimeContributionBannerMutation({
      environment,
      repositoryId: data.id,
    })
  }, [environment, data.id])

  const dismissForAllRepos = useCallback(() => {
    dismissFirstTimeContributionBannerMutation({environment, repositoryId: data.id})
  }, [environment, data.id])

  useEffect(() => {
    if (!data.showFirstTimeContributorBanner) return

    loadBannerLazyData({node: data.id})
  }, [loadBannerLazyData, data])

  const bannerWithoutLazyData = useMemo(
    () => (
      <FirstTimeContributionBannerDisplay
        repoNameWithOwner={data.nameWithOwner}
        contributingGuidelinesUrl={undefined}
        hasGoodFirstIssueIssues={Boolean(data.communityProfile?.goodFirstIssueIssuesCount)}
        contributeUrl={`${data.url}/contribute`}
        dismissForThisRepo={dismissForThisRepo}
        dismissForAllRepos={dismissForAllRepos}
      />
    ),
    [
      data.nameWithOwner,
      data.communityProfile?.goodFirstIssueIssuesCount,
      data.url,
      dismissForThisRepo,
      dismissForAllRepos,
    ],
  )

  if (!data.showFirstTimeContributorBanner) {
    return null
  }

  if (!bannerLazyDataRef) {
    return bannerWithoutLazyData
  }

  return (
    <Suspense fallback={bannerWithoutLazyData}>
      <FirstTimeContributionBannerInternal
        queryRef={bannerLazyDataRef}
        data={data}
        dismissForThisRepo={dismissForThisRepo}
        dismissForAllRepos={dismissForAllRepos}
      />
    </Suspense>
  )
}

type FirstTimeContributionBannerInternalProps = {
  queryRef: PreloadedQuery<FirstTimeContributionBannerContributingGuidelinesQuery>
  dismissForThisRepo: () => void
  dismissForAllRepos: () => void
  data: FirstTimeContributionBanner$data
}

const FirstTimeContributionBannerInternal = ({
  data,
  queryRef,
  dismissForAllRepos,
  dismissForThisRepo,
}: FirstTimeContributionBannerInternalProps) => {
  const {node} = usePreloadedQuery<FirstTimeContributionBannerContributingGuidelinesQuery>(
    FirstTimeContributionBannerContributingGuidelinesGraphqlQuery,
    queryRef,
  )

  return (
    <FirstTimeContributionBannerDisplay
      repoNameWithOwner={data.nameWithOwner}
      contributingGuidelinesUrl={node?.contributingGuidelines?.firstTimeContributionLink ?? undefined}
      hasGoodFirstIssueIssues={Boolean(data.communityProfile?.goodFirstIssueIssuesCount)}
      contributeUrl={`${data.url}/contribute`}
      dismissForThisRepo={dismissForThisRepo}
      dismissForAllRepos={dismissForAllRepos}
    />
  )
}
