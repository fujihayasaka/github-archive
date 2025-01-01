import type {Meta, StoryObj} from '@storybook/react'
import type {StepData} from './Stepper/Stepper'
import GettingStarted, {type GettingStartedProps} from './GettingStarted'

const exampleInitialSteps: StepData[] = [
  {
    title: 'Complete your profile',
    description:
      'Add your personal bio, avatar, and update your README file — express yourself by building your social coding presence on GitHub.',
    ctaLabel: 'Update profile',
  },
  {
    title: 'Create a project with Copilot',
    description: 'Ask Copilot questions about coding with GitHub or start writing code for your first project.',
    ctaLabel: 'Start project',
  },
  {
    title: 'Create your first repository',
    description:
      'Repositories are where your projects live on GitHub and are the main tool used to collaborate with others. ',
    ctaLabel: 'Create repo',
  },
]

const onChecklistChange = (checklist: boolean[]) => {
  // eslint-disable-next-line no-console
  console.log('Checklist changed:', checklist)
}

const onDismiss = () => {
  alert('Checklist dismissed!')
}

const meta = {
  title: 'Recipes/GettingStarted',
  component: GettingStarted,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  args: {
    dismissed: false,
    checklist: [false, false, false],
    stepMetadata: exampleInitialSteps,
    onChecklistChange,
    onDismiss,
  },
  argTypes: {
    stepMetadata: {
      control: false,
      table: {
        disable: true,
      },
    },
  },
} satisfies Meta<typeof GettingStarted>

export default meta

type Story = StoryObj<typeof GettingStarted>

export const Default: Story = {
  render: (args: GettingStartedProps) => {
    return (
      <div style={{width: '800px'}}>
        <GettingStarted key={`${args.dismissed}-${args.checklist.join(',')}`} {...args} />
      </div>
    )
  },
}
