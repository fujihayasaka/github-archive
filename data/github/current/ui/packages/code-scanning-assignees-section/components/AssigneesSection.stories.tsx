import type {Meta} from '@storybook/react'
import {HttpResponse, http} from 'msw'
import {AssigneesSection, type AssigneesSectionProps} from './AssigneesSection'
import {Title, Controls} from '@storybook/blocks'
import {getAssignee, getAssigneesSectionProps} from '../test-utils/mock-data'
import type {AvailableAssigneesResponse} from '../hooks/use-available-assignees-query'
import type {UpdateAlertAssigneesResponse} from '../hooks/use-update-alert-assignees-mutation'

const monalisa = getAssignee()
const octocat = getAssignee({
  id: 2,
  login: 'octocat',
  name: null,
  avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
  profilePath: '/octocat',
})
const copilot = getAssignee({
  id: 3789,
  login: 'Copilot',
  name: null,
  avatarUrl: 'https://avatars.githubusercontent.com/u/3789?v=4',
  profilePath: '/apps/copilot-swe-agent',
  isCopilot: true,
})
const octocats = Array.from({length: 25}, (_, i) => {
  return getAssignee({
    id: i + 3,
    login: `octocat${i + 3}`,
    name: null,
    avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
    profilePath: `/octocat${i + 3}`,
  })
})
const availableAssignees = [octocat, monalisa, copilot, ...octocats]

const meta = {
  title: 'Code Scanning Assignees Section/Assignees Section',
  component: AssigneesSection,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    docs: {
      page: () => (
        <>
          <Title />
          <Controls />
        </>
      ),
    },
    msw: {
      handlers: [
        http.get(`/monalisa/happy/security/code-scanning/available-assignees`, () => {
          return HttpResponse.json({
            users: availableAssignees,
          } satisfies AvailableAssigneesResponse)
        }),
        http.patch(`/monalisa/happy/security/code-scanning/123/assignees`, async ({request}) => {
          const {assignee_ids: assigneeIds} = (await request.json()) as {assignee_ids: number[]}

          return HttpResponse.json({
            assignees: availableAssignees.filter(assignee => assigneeIds.includes(assignee.id)),
          } satisfies UpdateAlertAssigneesResponse)
        }),
      ],
    },
  },
  argTypes: {},
} satisfies Meta<typeof AssigneesSection>

export default meta

const defaultArgs: Partial<AssigneesSectionProps> = getAssigneesSectionProps({
  assignees: [],
})

export const NoOneAssigned = {
  args: defaultArgs,
  render: (args: AssigneesSectionProps) => <AssigneesSection {...args} />,
}

export const NoOneAssignedReadonly = {
  args: {
    ...defaultArgs,
    readonly: true,
  },
  render: (args: AssigneesSectionProps) => <AssigneesSection {...args} />,
}

export const MultipleAssignees = {
  args: {
    ...defaultArgs,
    assignees: availableAssignees.slice(1, 3),
  },
  render: (args: AssigneesSectionProps) => <AssigneesSection {...args} />,
}

export const MultipleAssigneesReadonly = {
  args: {
    ...defaultArgs,
    assignees: availableAssignees.slice(1, 3),
    readonly: true,
  },
  render: (args: AssigneesSectionProps) => <AssigneesSection {...args} />,
}
