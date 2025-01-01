import {commitMutation, graphql, type Environment} from 'react-relay'
import type {dismissFirstTimeContributionBannerForRepoMutation} from './__generated__/dismissFirstTimeContributionBannerForRepoMutation.graphql'

type DismissFirstTimeContributionBannerForRepoMutationProps = {
  environment: Environment
  repositoryId: string
}

const notice = 'first_time_contributor_issues_banner'

export function dismissRepoFirstTimeContributionBannerMutation({
  environment,
  repositoryId,
}: DismissFirstTimeContributionBannerForRepoMutationProps) {
  return commitMutation<dismissFirstTimeContributionBannerForRepoMutation>(environment, {
    mutation: graphql`
      mutation dismissFirstTimeContributionBannerForRepoMutation($input: DismissRepositoryNoticeInput!) {
        dismissRepositoryNotice(input: $input) {
          clientMutationId
        }
      }
    `,
    variables: {
      input: {notice, repositoryId},
    },
    updater: store => {
      const repository = store.get(repositoryId)
      if (!repository) return

      repository.setValue(false, 'showFirstTimeContributorBanner(isPullRequests:false)')
    },
  })
}
