import type {Meta} from '@storybook/react'

import {Stepper, type StepData} from './Stepper'
import {useState} from 'react'

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

const meta = {
  title: 'Recipes/GettingStarted/Stepper',
  component: Stepper,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof Stepper>

export default meta

export const Default = () => {
  const [activeStep, setActiveStep] = useState(0)
  const [steps, setSteps] = useState(exampleInitialSteps)

  const handleStepChange = (index: number) => {
    setActiveStep(index)
  }

  const handleStepComplete = (index: number) => {
    setActiveStep(index + 1)
    setSteps(prev => prev.map((step, i) => (i === index ? {...step, isComplete: true} : step)))
  }

  return (
    <div style={{width: '800px'}}>
      <Stepper
        steps={steps}
        activeStepIndex={activeStep}
        onStepChange={handleStepChange}
        onStepComplete={handleStepComplete}
      />
    </div>
  )
}
