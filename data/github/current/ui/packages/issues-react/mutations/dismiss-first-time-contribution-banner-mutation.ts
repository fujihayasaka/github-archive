import {commitMutation, graphql} from 'react-relay'
import type {Environment} from 'relay-runtime'
import type {dismissFirstTimeContributionBannerMutation} from './__generated__/dismissFirstTimeContributionBannerMutation.graphql'

export type DismissFirstTimeContributionBannerMutationProps = {
  environment: Environment
  repositoryId: string
}

const notice = 'first_time_contributor_issues_banner'

export function dismissFirstTimeContributionBannerMutation({
  environment,
  repositoryId,
}: DismissFirstTimeContributionBannerMutationProps) {
  return commitMutation<dismissFirstTimeContributionBannerMutation>(environment, {
    mutation: graphql`
      mutation dismissFirstTimeContributionBannerMutation($input: DismissNoticeInput!) {
        dismissNotice(input: $input) {
          clientMutationId
        }
      }
    `,
    variables: {
      input: {notice},
    },
    updater: store => {
      const repository = store.get(repositoryId)
      if (!repository) return

      repository.setValue(false, 'showFirstTimeContributorBanner(isPullRequests:false)')
    },
  })
}
