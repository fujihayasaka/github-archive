import {ActionList} from '@primer/react'
import {CopilotIcon} from '@primer/octicons-react'
import {hovercardAttributesForActor} from '@github-ui/hovercards'
import {GitHubAvatar} from '@github-ui/github-avatar'
import type {Assignee} from '../types'
import {LABELS} from '@github-ui/item-picker/Labels'

export type AssigneesListProps = {
  assignees: Assignee[]
}

export function AssigneesList({assignees}: AssigneesListProps) {
  return (
    <ActionList variant="full" className="py-0">
      {assignees.sort(sortByLogin).map(assignee => {
        return (
          <ActionList.LinkItem
            key={assignee.id}
            href={assignee.profilePath}
            target="_blank"
            {...hovercardAttributesForActor(assignee.login, {isCopilot: assignee.isCopilot})}
          >
            <ActionList.LeadingVisual>
              {assignee.isCopilot ? (
                <CopilotIcon className="color-fg-default" />
              ) : (
                <GitHubAvatar alt={`@${assignee.login}`} src={assignee.avatarUrl} />
              )}
            </ActionList.LeadingVisual>
            <span className="mx-0 width-full f6 text-bold">
              {assignee.isCopilot ? LABELS.copilotDisplayName : assignee.login}
            </span>
          </ActionList.LinkItem>
        )
      })}
    </ActionList>
  )
}

function sortByLogin(a: Assignee, b: Assignee) {
  return a.login === b.login ? 0 : a.login > b.login ? 1 : -1
}
