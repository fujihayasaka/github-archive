import type {Meta} from '@storybook/react'
import {CopilotPlanBrainstormButton, type CopilotPlanBrainstormButtonProps} from './CopilotPlanBrainstormButton'

const meta = {
  title: 'Recipes/CopilotPlanBrainstormButton',
  component: CopilotPlanBrainstormButton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    markdown: {control: 'text', defaultValue: 'Hello, Storybook!'},
  },
} satisfies Meta<typeof CopilotPlanBrainstormButton>

export default meta

const defaultArgs: Partial<CopilotPlanBrainstormButtonProps> = {
  markdown: 'Hello, Storybook!',
}

export const CopilotPlanBrainstormExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: CopilotPlanBrainstormButtonProps) => <CopilotPlanBrainstormButton {...args} />,
}
