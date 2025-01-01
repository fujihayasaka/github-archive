import type {Meta, StoryObj} from '@storybook/react'
import {UnsafeHTMLDiv} from './UnsafeHTML'
import {unsafeHTMLString} from './__tests__/utils/mocks'

const meta = {
  title: 'Utilities/safe-html/UnsafeHTMLDiv',
  component: UnsafeHTMLDiv,
  args: {
    html: unsafeHTMLString,
  },
} satisfies Meta<typeof UnsafeHTMLDiv>

export default meta

type Story = StoryObj<typeof UnsafeHTMLDiv>

export const Example: Story = {}

export const WithStrictConfig: Story = {
  args: {
    domPurifyConfig: {
      ALLOWED_TAGS: ['p', 'h2', 'strong', 'em', 'a'],
      ALLOWED_ATTR: ['href', 'class'], // only allow href and class attributes
    },
  },
}

export const WithVeryStrictConfig: Story = {
  args: {
    domPurifyConfig: {
      ALLOWED_TAGS: ['p', 'h2'],
      ALLOWED_ATTR: [], // no attributes allowed at all
    },
  },
}
