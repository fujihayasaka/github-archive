import {GitHubAvatar} from '@github-ui/github-avatar'
import type {PlanInfo} from '../../../types'

type Props = {
  planInfo: PlanInfo
  account?: string
}

export function AccountButtonAvatar({planInfo, account}: Props) {
  if (planInfo.currentUser && account === planInfo.currentUser.displayLogin && planInfo.currentUser.image) {
    // Return the current user avatar if the current user is selected
    return <GitHubAvatar square src={planInfo.currentUser.image} data-testid="user-account-avatar" />
  } else {
    // Otherwise, find the matching organization
    const matchingOrg = planInfo.organizations.find(org => account === org.displayLogin && org.image)
    if (matchingOrg && matchingOrg.image) {
      return <GitHubAvatar square src={matchingOrg.image} data-testid="org-account-avatar" />
    }
  }
  return null
}
