import type {Meta} from '@storybook/react'
import {BypassList, type BypassListProps} from './BypassList'
import {getBypassActor} from '../../test-utils/mock-data'

const meta = {
  title: 'Recipes/BypassActors/BypassList',
  component: BypassList,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    readOnly: {control: 'boolean', defaultValue: false},
    isBypassModeEnabled: {control: 'boolean', defaultValue: false},
  },
} satisfies Meta<typeof BypassList>

export default meta

const defaultArgs: Partial<BypassListProps> = {
  readOnly: false,
  isBypassModeEnabled: false,
  removeBypassActor: () => null,
  updateBypassActor: () => null,
  enabledBypassActors: [],
  baseAvatarUrl: 'https://avatars.githubusercontent.com',
}

export const BypassListExample = {
  args: {
    ...defaultArgs,
    enabledBypassActors: [getBypassActor(1, 'Team'), getBypassActor(2, 'Team')],
  },
  render: (args: BypassListProps) => (
    <ul>
      <BypassList {...args} />
    </ul>
  ),
}
