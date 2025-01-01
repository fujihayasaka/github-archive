import type {Meta, StoryObj} from '@storybook/react'
import {UnsafeHTMLText} from './UnsafeHTML'
import {unsafeHTMLTextString} from './__tests__/utils/mocks'

const meta = {
  title: 'Utilities/safe-html/UnsafeHTMLText',
  component: UnsafeHTMLText,
  args: {
    html: unsafeHTMLTextString,
  },
} satisfies Meta<typeof UnsafeHTMLText>

export default meta

type Story = StoryObj<typeof UnsafeHTMLText>

export const Example: Story = {}

export const Variant: Story = {
  args: {
    size: 'large',
    weight: 'semibold',
  },
}

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
