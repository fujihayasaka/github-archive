import type {Meta} from '@storybook/react'
import {CodeMenuButton, type CodeMenuButtonProps} from './CodeMenuButton'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Recipes/CodeMenuButton',
  component: CodeMenuButton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    isPrimary: {control: 'boolean', defaultValue: false},
  },
} satisfies Meta<typeof CodeMenuButton>

export default meta

const defaultArgs: CodeMenuButtonProps = {
  isPrimary: false,
  children: <div />,
}

export const LocalOnly = {
  args: defaultArgs,
  render: (args: CodeMenuButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeMenuButton {...args} />
    </Wrapper>
  ),
}

export const CodespacesEnabled = {
  args: {
    ...defaultArgs,
    showCodespacesTab: true,
  },
  render: (args: CodeMenuButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeMenuButton {...args} />
    </Wrapper>
  ),
}

export const CopilotEnabled = {
  args: {
    ...defaultArgs,
    showCopilotTab: true,
  },
  render: (args: CodeMenuButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeMenuButton {...args} />
    </Wrapper>
  ),
}

export const AllTabsEnabled = {
  args: {
    ...defaultArgs,
    showCodespacesTab: true,
    showCopilotTab: true,
  },
  render: (args: CodeMenuButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeMenuButton {...args} />
    </Wrapper>
  ),
}

export const IsisPrimary = {
  args: {
    ...defaultArgs,
    isPrimary: true,
  },
  render: (args: CodeMenuButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeMenuButton {...args} />
    </Wrapper>
  ),
}

export const isEnterprise = {
  args: {
    ...defaultArgs,
  },
  render: (args: CodeMenuButtonProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <CodeMenuButton {...args} />
    </Wrapper>
  ),
}
