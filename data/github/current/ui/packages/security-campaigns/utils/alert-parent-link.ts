import {campaignRepoPath, repositoryPath} from '@github-ui/paths'
import type {AlertParentLink} from '../types/security-campaign-alert'

export const alertParentLinkHref = (
  alertParentLink: AlertParentLink | undefined,
  {owner, repo}: {owner: string; repo: string},
) => {
  if (!alertParentLink) {
    return undefined
  }

  if (alertParentLink.kind === 'repository') {
    return repositoryPath({owner, repo})
  }

  if (alertParentLink.kind === 'campaign') {
    return campaignRepoPath({
      owner,
      repo,
      campaignNumber: alertParentLink.campaignNumber,
    })
  }

  return undefined
}
