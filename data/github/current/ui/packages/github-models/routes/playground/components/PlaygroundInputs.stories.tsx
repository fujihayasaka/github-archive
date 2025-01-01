import {type PropsWithChildren, useMemo} from 'react'
import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {PlaygroundInputs} from './PlaygroundInputs'
import {PlaygroundManagerContext, Panel, type PlaygroundManager} from '../../../utils/playground-manager'
import {mockModelState} from './__tests__/mocks'
import {SidebarSelectionOptions} from '../../../types'
import {panelPositionArgType, parametersConfig} from '../../../utils/story-utils'

const modelState = mockModelState({parametersHasChanges: true})

type StoryArgs = typeof PlaygroundInputs

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundInputs',
  component: PlaygroundInputs,
  args: {
    model: modelState,
    position: Panel.Main,
    showSidebar: true,
    showSidebarOnMobile: true,
    handleSetSidebarTab: fn(),
    handleShowSidebar: fn(),
    handleShowSidebarOnMobile: fn(),
  },
  argTypes: {
    model: {control: {type: 'object'}},
    position: panelPositionArgType,
    sidebarTab: {control: false},
    showSidebar: {control: 'boolean'},
    showSidebarOnMobile: {control: 'boolean'},
    handleSetSidebarTab: {control: false},
    handleShowSidebar: {control: false},
    handleShowSidebarOnMobile: {control: false},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

function StoryWrapper({children}: PropsWithChildren) {
  const manager = useMemo(() => ({}) as PlaygroundManager, [])
  manager.resetParamsAndSystemPrompt = fn()

  return (
    <Wrapper pathname={ModelUrlHelper.playgroundUrl(modelState.catalogData)}>
      <PlaygroundManagerContext.Provider value={manager}>{children}</PlaygroundManagerContext.Provider>
    </Wrapper>
  )
}

export const ParametersTab: Story = {
  render: args => <PlaygroundInputs {...args} />,
  args: {
    sidebarTab: SidebarSelectionOptions.PARAMETERS,
  },
  decorators: [
    Story => (
      <StoryWrapper>
        <Story />
      </StoryWrapper>
    ),
  ],
}

export const DetailsTab: Story = {
  render: args => <PlaygroundInputs {...args} />,
  args: {
    sidebarTab: SidebarSelectionOptions.DETAILS,
  },
  decorators: [
    Story => (
      <StoryWrapper>
        <Story />
      </StoryWrapper>
    ),
  ],
}
