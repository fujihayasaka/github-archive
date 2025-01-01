import type {Meta} from '@storybook/react'
import {SyntaxHighlightedLine, type SyntaxHighlightedLineProps} from './SyntaxHighlightedLine'

const meta = {
  title: 'Syntax Highlighted Lines',
  component: SyntaxHighlightedLine,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof SyntaxHighlightedLine>

export default meta

const defaultArgs: Partial<SyntaxHighlightedLineProps> = {
  html: "import '@testing-library/jest-dom'",
  styleDirectives: [
    {s: 0, e: 6, c: 'pl-k'},
    {s: 7, e: 34, c: 'pl-s'},
  ],
}

export const SyntaxHighlightedLinesExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: SyntaxHighlightedLineProps) => <SyntaxHighlightedLine {...args} />,
}
