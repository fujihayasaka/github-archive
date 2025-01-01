import {GitHubAvatar} from '@github-ui/github-avatar'
import {ShieldLockIcon} from '@primer/octicons-react'
import type {ActionListItemProps} from '@primer/react'

import type {CopilotChatOrg} from '../../utils/copilot-chat-types'
import {LinkSuggestion} from './LinkSuggestion'
import {MultistepSuggestion} from './MultistepSuggestion'

interface SSOOrgSuggestionProps extends ActionListItemProps {
  org: CopilotChatOrg
}

export function SSOOrgSuggestion({org, ...props}: SSOOrgSuggestionProps) {
  return (
    <LinkSuggestion leadingVisual={<GitHubAvatar square src={org.avatarUrl} />} {...props}>
      {org.login}
    </LinkSuggestion>
  )
}

interface SSOPromptSuggestionProps extends ActionListItemProps {
  orgs: CopilotChatOrg[]
}

export function SSOPromptSuggestion({orgs, ...props}: SSOPromptSuggestionProps) {
  return orgs.length === 1 ? (
    <LinkSuggestion leadingVisual={<ShieldLockIcon />} {...props}>
      Single sign-on to <strong>{orgs[0]?.login}</strong> for more
    </LinkSuggestion>
  ) : (
    <MultistepSuggestion leadingVisual={<ShieldLockIcon />} {...props}>
      Single sign-on for more
    </MultistepSuggestion>
  )
}
