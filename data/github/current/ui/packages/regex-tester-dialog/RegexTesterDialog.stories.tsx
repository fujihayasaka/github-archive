import type {Meta} from '@storybook/react'
import {RegexTesterDialog, type RegexTesterDialogProps} from './RegexTesterDialog'
import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Recipes/RegexTesterDialog',
  component: RegexTesterDialog,
  parameters: {
    a11y: disableA11yRuleForDialog,
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof RegexTesterDialog>

export default meta

const defaultArgs: Partial<RegexTesterDialogProps> = {
  onDismiss: () => null,
  regexPattern: 'abc',
  regexPatternValidationError: '',
  onRegexPatternChange: () => null,
  returnFocusRef: undefined,
}

export const RegexTesterDialogExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: RegexTesterDialogProps) => <RegexTesterDialog {...args} />,
}
