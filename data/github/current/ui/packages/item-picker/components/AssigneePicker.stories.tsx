import {DefaultAssigneePickerAnchor} from './DefaultAssigneePickerAnchor'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {noop} from '@github-ui/noop'
import type {AssigneePickerSearchAssignableRepositoryUsersQuery} from './__generated__/AssigneePickerSearchAssignableRepositoryUsersQuery.graphql'
import {AssigneeRepositoryPicker} from './AssigneePicker'

type AssigneePickerQueries = {
  assignees: AssigneePickerSearchAssignableRepositoryUsersQuery
}

function TestAssigneeRepositoryPicker() {
  return (
    <AssigneeRepositoryPicker
      readonly={false}
      shortcutEnabled
      assignees={[]}
      assigneeTokens={[]}
      repo="issues"
      owner="github"
      onSelectionChange={noop}
      includeAssignableBots
      includeAuthorableBots
      anchorElement={anchorProps => (
        <DefaultAssigneePickerAnchor assignees={[]} readonly={!true} anchorProps={anchorProps} />
      )}
    />
  )
}

const meta: Meta<typeof AssigneeRepositoryPicker> = {
  title: 'ItemPicker/AssigneePicker',
  component: TestAssigneeRepositoryPicker,
}

export default meta

export const DefaultState = {
  decorators: [relayDecorator],
  parameters: {
    relay: {
      queries: {
        assignees: {
          type: 'lazy',
        },
      },
      mockResolvers: {
        User() {
          return {
            id: mockRelayId(),
            login: 'viewerLogin',
            name: 'viewerName',
          }
        },
      },
      mapStoryArgs: () => ({
        assignees: [],
        participants: [],
      }),
    },
  },
} satisfies RelayStoryObj<typeof AssigneeRepositoryPicker, AssigneePickerQueries>
