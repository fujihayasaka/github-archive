import type {Meta} from '@storybook/react'
import {OrgSelector, type BaseOrganization, type MutliOrgSelectorProps} from './OrgSelector'

const meta = {
  title: 'Recipes/OrgSelector',
  component: OrgSelector,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof OrgSelector>

export default meta

const defaultArgs: Partial<MutliOrgSelectorProps<BaseOrganization>> = {
  selection: [],
  selectOrg: () => {},
  removeOrg: () => {},
  orgLoader: async () => {
    return [
      {id: 0, nodeId: '0', name: 'Org 0'},
      {id: 1, nodeId: '1', name: 'Org 1'},
      {id: 2, nodeId: '2', name: 'Org 2'},
      {id: 3, nodeId: '3', name: 'Org 3'},
      {id: 4, nodeId: '4', name: 'Org 4'},
    ]
  },
}

export const OrgSelectorExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: MutliOrgSelectorProps<BaseOrganization>) => <OrgSelector {...args} />,
}
