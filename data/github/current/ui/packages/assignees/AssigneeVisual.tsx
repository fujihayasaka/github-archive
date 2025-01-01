import {CopilotIcon} from '@primer/octicons-react'
import {isCopilot} from './copilot-user'
import {GitHubAvatar} from '@github-ui/github-avatar'

export type AssigneeVisualProps = {login: string; id: string; avatarUrl: string}

export function AssigneeVisual({login, id, avatarUrl}: AssigneeVisualProps) {
  if (isCopilot(login)) {
    return <CopilotIcon />
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
