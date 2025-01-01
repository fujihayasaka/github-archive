import type {Meta, StoryObj} from '@storybook/react'

import {RepositoryListItem, type RepositoryListItemProps} from './RepositoryListItem'

const meta = {
  title: 'Apps/Copilot/RepositoryListItem',
  component: RepositoryListItem,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof RepositoryListItem>

export default meta

const defaultArgs: RepositoryListItemProps = {
  onSelect: () => {},
  repo: {
    databaseId: 1,
    isInOrganization: false,
    name: 'smile',
    nwo: 'monalisa/smile',
    ownerAvatarUrl: '',
    ownerLogin: 'monalisa',
  },
}

export const Default: StoryObj<RepositoryListItemProps> = {
  args: {...defaultArgs},
  render: args => (
    <ul>
      <RepositoryListItem {...args} />
    </ul>
  ),
}
