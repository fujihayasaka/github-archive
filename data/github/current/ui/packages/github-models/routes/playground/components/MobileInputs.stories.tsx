import type {Meta, StoryObj} from '@storybook/react'
import {SidebarSelectionOptions} from '../../../types'
import {fn} from '@storybook/test'
import {mockModelState} from './__tests__/mocks'
import {MobileInputs} from './MobileInputs'
import {Panel} from '../../../utils/playground-manager'
import {panelPositionArgType, parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof MobileInputs

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/MobileInputs',
  component: MobileInputs,
  args: {
    modelState: mockModelState(),
    position: Panel.Main,
    resetLabel: 'Reset this please',
    handleShowSidebarOnMobile: fn(),
    doReset: fn(),
  },
  argTypes: {
    modelState: {control: 'object'},
    sidebarTab: {control: false},
    position: panelPositionArgType,
    resetLabel: {control: 'text'},
    handleShowSidebarOnMobile: {control: false},
    doReset: {control: false},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const DetailsTab: Story = {
  render: args => <MobileInputs {...args} sidebarTab={SidebarSelectionOptions.DETAILS} />,
}

export const ParametersTab: Story = {
  render: args => <MobileInputs {...args} sidebarTab={SidebarSelectionOptions.PARAMETERS} />,
}
