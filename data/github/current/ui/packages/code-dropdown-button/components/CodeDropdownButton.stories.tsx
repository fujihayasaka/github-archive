import type {Meta} from '@storybook/react'
import {CodeDropdownButton, type CodeDropdownButtonProps} from './CodeDropdownButton'
import {testCodeButtonPayload} from '../__tests__/test-helpers'
import {LocalTab} from './LocalTab'
import {CodespacesTab} from './CodespacesTab'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Recipes/CodeDropdownButton',
  component: CodeDropdownButton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    primary: {control: 'boolean', defaultValue: false},
  },
} satisfies Meta<typeof CodeDropdownButton>

export default meta

const defaultArgs: CodeDropdownButtonProps = {
  primary: false,
  showCodespacesTab: false,
  isEnterprise: false,
  localTab: <LocalTab {...testCodeButtonPayload.local} />,
  codespacesTab: <CodespacesTab {...testCodeButtonPayload.codespaces} />,
}

export const LocalOnly = {
  args: defaultArgs,
  render: (args: CodeDropdownButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeDropdownButton {...args} />
    </Wrapper>
  ),
}

export const CodespacesEnabled = {
  args: {
    ...defaultArgs,
    showCodespacesTab: true,
  },
  render: (args: CodeDropdownButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeDropdownButton {...args} />
    </Wrapper>
  ),
}

export const AllTabsEnabled = {
  args: {
    ...defaultArgs,
    showCodespacesTab: true,
  },
  render: (args: CodeDropdownButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeDropdownButton {...args} />
    </Wrapper>
  ),
}

export const IsPrimary = {
  args: {
    ...defaultArgs,
    primary: true,
  },
  render: (args: CodeDropdownButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeDropdownButton {...args} />
    </Wrapper>
  ),
}

export const isEnterprise = {
  args: {
    ...defaultArgs,
    isEnterprise: true,
  },
  render: (args: CodeDropdownButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeDropdownButton {...args} />
    </Wrapper>
  ),
}
