import type {Meta, StoryObj} from '@storybook/react'
import type {AlertLinksButton} from '../AlertLinksButton'
import {createRepository, getAutofixValidationCheck} from '../../test-utils/mock-data'
import {AutofixValidationChecksButton, type AutofixValidationChecksButtonProps} from '../AutofixValidationChecksButton'
import {AutofixValidationCheckStatus, AutofixValidationType} from '../../types/autofix-validation-check'

const meta = {
  title: 'Apps/Security Campaigns/Autofix validation checks button',
  component: AutofixValidationChecksButton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof AlertLinksButton>

export default meta

const defaultArgs: AutofixValidationChecksButtonProps = {
  validationChecks: [
    getAutofixValidationCheck({
      validationType: AutofixValidationType.Llm,
    }),
    getAutofixValidationCheck({
      validationType: AutofixValidationType.CodeQL,
    }),
    getAutofixValidationCheck({
      validationType: AutofixValidationType.Linter,
    }),
  ],
  repository: createRepository(),
}

type Story = StoryObj<typeof AutofixValidationChecksButton>

export const PassingValidationChecks: Story = {
  args: {
    ...defaultArgs,
  },
  render: (args: AutofixValidationChecksButtonProps) => <AutofixValidationChecksButton {...args} />,
}

export const PartiallyPassingValidationChecks: Story = {
  args: {
    ...defaultArgs,
    validationChecks: [
      ...defaultArgs.validationChecks.slice(0, 2),
      getAutofixValidationCheck({
        validationType: AutofixValidationType.Linter,
        status: AutofixValidationCheckStatus.Failed,
      }),
    ],
  },
  render: (args: AutofixValidationChecksButtonProps) => <AutofixValidationChecksButton {...args} />,
}

export const AllFailedValidationChecks: Story = {
  args: {
    ...defaultArgs,
    validationChecks: defaultArgs.validationChecks.map(check => ({
      ...check,
      status: AutofixValidationCheckStatus.Failed,
    })),
  },
  render: (args: AutofixValidationChecksButtonProps) => <AutofixValidationChecksButton {...args} />,
}

export const AllPendingValidationChecks: Story = {
  args: {
    ...defaultArgs,
    validationChecks: defaultArgs.validationChecks.map(check => ({
      ...check,
      status: AutofixValidationCheckStatus.Pending,
    })),
  },
  render: (args: AutofixValidationChecksButtonProps) => <AutofixValidationChecksButton {...args} />,
}

export const SomePendingAndPassingValidationChecks: Story = {
  args: {
    ...defaultArgs,
    validationChecks: [
      ...defaultArgs.validationChecks,
      getAutofixValidationCheck({
        validationType: AutofixValidationType.Tests,
        status: AutofixValidationCheckStatus.Pending,
      }),
    ],
  },
  render: (args: AutofixValidationChecksButtonProps) => <AutofixValidationChecksButton {...args} />,
}

export const SomePendingAndFailingValidationChecks: Story = {
  args: {
    ...defaultArgs,
    validationChecks: [
      ...defaultArgs.validationChecks.map(check => ({
        ...check,
        status: AutofixValidationCheckStatus.Failed,
      })),
      getAutofixValidationCheck({
        validationType: AutofixValidationType.Tests,
        status: AutofixValidationCheckStatus.Pending,
      }),
    ],
  },
  render: (args: AutofixValidationChecksButtonProps) => <AutofixValidationChecksButton {...args} />,
}

export const NoValidationChecks = {
  args: {
    ...defaultArgs,
    validationChecks: [],
  },
  render: (args: AutofixValidationChecksButtonProps) => <AutofixValidationChecksButton {...args} />,
}
