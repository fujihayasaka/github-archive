import {GitPullRequestIcon, type Icon} from '@primer/octicons-react'

import type {CommandContext} from './use-command-context'

function detailsForContext(context: CommandContext): {name: string; icon: Icon} | undefined {
  switch (context.type) {
    case 'pull-request':
      return {
        name: `${context.number}`,
        icon: GitPullRequestIcon,
      }
  }

  return undefined
}

export function ContextLabel({context}: {context?: CommandContext}): JSX.Element | undefined {
  if (!context) {
    return undefined
  }

  const details = detailsForContext(context)
  if (!details) {
    return undefined
  }

  const {icon: Icon, name} = details
  return (
    <div className="fgColor-muted bgColor-muted px-2 py-1 rounded-2 f6">
      {Icon && <Icon className="mr-1 fgColor-open" size="small" />}
      {name}
    </div>
  )
}
