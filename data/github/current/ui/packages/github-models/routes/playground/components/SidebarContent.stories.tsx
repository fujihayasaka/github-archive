import type {Meta, StoryObj} from '@storybook/react'
import {SidebarContent} from './SidebarContent'
import {SidebarSelectionOptions} from '../../../types'
import {mockModelState} from './__tests__/mocks'
import {Panel} from '../../../utils/playground-manager'
import {panelPositionArgType, parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof SidebarContent

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/SidebarContent',
  component: SidebarContent,
  args: {
    modelState: mockModelState(),
    position: Panel.Main,
  },
  argTypes: {
    activeTab: {control: false},
    modelState: {control: 'object'},
    position: panelPositionArgType,
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const DetailsTab: Story = {
  render: args => <SidebarContent {...args} activeTab={SidebarSelectionOptions.DETAILS} />,
}

export const ParametersTab: Story = {
  render: args => <SidebarContent {...args} activeTab={SidebarSelectionOptions.PARAMETERS} />,
}
