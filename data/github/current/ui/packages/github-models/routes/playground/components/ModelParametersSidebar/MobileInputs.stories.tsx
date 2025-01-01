import type {Meta, StoryObj, StoryFn, StoryContext} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {modelPlaygroundPath} from '@github-ui/paths'
import {SidebarSelectionOptions} from '../../../../types'
import {fn} from '@storybook/test'
import {mockModelState} from '../__tests__/mocks'
import {MobileInputs} from './MobileInputs'
import {Panel, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import {panelPositionArgType, parametersConfig} from '../../../../utils/story-utils'

type StoryArgs = typeof MobileInputs

const modelState = mockModelState()

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/MobileInputs',
  component: MobileInputs,
  args: {
    modelState,
    position: Panel.Main,
    resetLabel: 'Reset this please',
    handleShowSidebarOnMobile: fn(),
    doReset: fn(),
    repository: undefined,
  },
  argTypes: {
    modelState: {control: 'object'},
    sidebarTab: {control: false},
    position: panelPositionArgType,
    resetLabel: {control: 'text'},
    handleShowSidebarOnMobile: {control: false},
    doReset: {control: false},
    repository: {control: false},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>
type Decorator = (fn: StoryFn, c: StoryContext) => JSX.Element

const decorators: Decorator[] = [
  Story => {
    const manager = {} as PlaygroundManager
    manager.setParameters = fn()
    manager.setParametersHasChanges = fn()
    manager.setSystemPrompt = fn()
    manager.setIsUseIndexSelected = fn()

    return (
      <Wrapper pathname={modelPlaygroundPath(modelState.catalogData)}>
        <PlaygroundManagerProvider manager={manager}>
          <Story />
        </PlaygroundManagerProvider>
      </Wrapper>
    )
  },
]

export const DetailsTab: Story = {
  render: args => <MobileInputs {...args} sidebarTab={SidebarSelectionOptions.DETAILS} />,
  decorators,
}

export const ParametersTab: Story = {
  render: args => <MobileInputs {...args} sidebarTab={SidebarSelectionOptions.PARAMETERS} />,
  decorators,
}
