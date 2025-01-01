import type {Meta, StoryObj} from '@storybook/react'
import {UnsafeHTMLBox} from './UnsafeHTML'
import {unsafeHTMLString} from './__tests__/utils/mocks'

const meta = {
  title: 'Utilities/safe-html/UnsafeHTMLBox',
  component: UnsafeHTMLBox,
  args: {
    html: unsafeHTMLString,
  },
} satisfies Meta<typeof UnsafeHTMLBox>

export default meta

type Story = StoryObj<typeof UnsafeHTMLBox>

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
