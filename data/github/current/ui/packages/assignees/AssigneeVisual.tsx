import {isCopilot} from './copilot-user'
import {CopilotAvatar} from '@github-ui/copilot-avatar'
import {CopilotIcon} from '@primer/octicons-react'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {GitHubAvatar} from '@github-ui/github-avatar'

export type AssigneeVisualProps = {login: string; id: string; avatarUrl: string}

export function AssigneeVisual({login, id, avatarUrl}: AssigneeVisualProps) {
  if (isCopilot(login)) {
    if (isFeatureEnabled('use_copilot_avatar')) {
      return <CopilotAvatar />
    } else {
      return <CopilotIcon />
    }
  } else {
    return (
      <GitHubAvatar
        src={avatarUrl}
        size={20}
        alt={`@${login}`}
        key={id}
        sx={{boxShadow: '0 0 0 2px var(--bgColor-muted, var(--color-canvas-subtle))'}}
      />
    )
  }
}
