import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {TokenizedQuery} from './TokenizedQuery'

const examples = [
  'repo:github',
  'user:"Mona Octocat"', // Quotes, whitespaces in the value
  '-visibility:private', // negation
  'prop.env:prod', // dot in key
  'multi:a,b,"c"', // multi value
  'help-wanted-issues:3', // dashes in key
  'plain-text-query',
]

const meta = {
  title: 'Recipes/FilterPicker/Components/TokenizedQuery',
  component: TokenizedQuery,
  decorators: [storyWrapper()],
  args: {
    query: examples.join(' '),
  },
} satisfies Meta<typeof TokenizedQuery>

export default meta

type Story = StoryObj<typeof TokenizedQuery>

export const Default = {}
export const Wrapping: Story = {
  decorators: [
    StoryComponent => (
      <div style={{width: '150px'}}>
        <StoryComponent />
      </div>
    ),
  ],
}
