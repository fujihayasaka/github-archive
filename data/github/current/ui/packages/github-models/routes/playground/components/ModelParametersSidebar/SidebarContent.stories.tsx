import type {Meta, StoryObj, StoryFn, StoryContext} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {fn} from '@storybook/test'
import {modelPlaygroundPath} from '@github-ui/paths'
import {SidebarContent} from './SidebarContent'
import {SidebarSelectionOptions} from '../../../../types'
import {mockModelState} from '../__tests__/mocks'
import {Panel, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import {panelPositionArgType, parametersConfig} from '../../../../utils/story-utils'

type StoryArgs = typeof SidebarContent

const modelState = mockModelState()

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/SidebarContent',
  component: SidebarContent,
  args: {
    modelState,
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
  render: args => <SidebarContent {...args} activeTab={SidebarSelectionOptions.DETAILS} />,
  decorators,
}

export const ParametersTab: Story = {
  render: args => <SidebarContent {...args} activeTab={SidebarSelectionOptions.PARAMETERS} />,
  decorators,
}
