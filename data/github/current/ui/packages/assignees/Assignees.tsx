import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import {userHovercardPath} from '@github-ui/paths'
import {ActionList, Box, type BetterSystemStyleObject} from '@primer/react'
import {AssigneeVisual} from './AssigneeVisual'
import {isCopilot} from './copilot-user'

export type AssigneesProps = {
  assignees: Assignee[]
  sx?: BetterSystemStyleObject
  testId?: string
}

export function Assignees({assignees, testId}: AssigneesProps) {
  return (
    <ActionList sx={{py: 0}} variant={'full'}>
      {assignees.sort(sortByLogin).map(assignee => (
        <ActionList.LinkItem
          key={assignee.id}
          href={`/${assignee.login}`}
          target="_blank"
          data-hovercard-url={userHovercardPath({owner: assignee.login})}
        >
          <ActionList.LeadingVisual>
            <AssigneeVisual login={assignee.login} id={assignee.id} avatarUrl={assignee.avatarUrl} />
          </ActionList.LeadingVisual>
          <Box sx={{mx: 0, width: '100%', fontSize: 0, fontWeight: '600'}} data-testid={testId}>
            {isCopilot(assignee.login) ? 'Copilot' : assignee.login}
          </Box>
        </ActionList.LinkItem>
      ))}
    </ActionList>
  )
}

function sortByLogin(a: Assignee, b: Assignee) {
  return a.login === b.login ? 0 : a.login > b.login ? 1 : -1
}
