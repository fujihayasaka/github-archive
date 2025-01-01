import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import {ActionList, Box, type BetterSystemStyleObject} from '@primer/react'
import {AssigneeVisual} from './AssigneeVisual'
import {isCopilot} from './copilot-user'
import {hovercardAttributesForActor} from '@github-ui/hovercards'
import {VALUES} from './constants/values'

export type AssigneesProps = {
  assignees: Assignee[]
  sx?: BetterSystemStyleObject
  testId?: string
}

export function Assignees({assignees, testId}: AssigneesProps) {
  return (
    <ActionList sx={{py: 0}} variant={'full'}>
      {assignees.sort(sortByLogin).map(assignee => {
        const {login, avatarUrl, profileResourcePath} = assignee
        const displayName = isCopilot(login) ? VALUES.copilot.displayName : login
        return (
          <ActionList.LinkItem
            key={assignee.id}
            href={profileResourcePath ?? undefined}
            target="_blank"
            {...hovercardAttributesForActor(login, {isCopilot: isCopilot(login)})}
          >
            <ActionList.LeadingVisual>
              <AssigneeVisual login={login} id={assignee.id} avatarUrl={avatarUrl} />
            </ActionList.LeadingVisual>
            <Box sx={{mx: 0, width: '100%', fontSize: 0, fontWeight: '600'}} data-testid={testId}>
              {displayName}
            </Box>
          </ActionList.LinkItem>
        )
      })}
    </ActionList>
  )
}

function sortByLogin(a: Assignee, b: Assignee) {
  return a.login === b.login ? 0 : a.login > b.login ? 1 : -1
}
