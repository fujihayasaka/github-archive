import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {AttachmentItem} from './AttachmentItem'
import {AttachmentPreviewImage} from './AttachmentPreviewImage'

const meta = {
  title: 'Apps/GitHub Models/Attachments/AttachmentItem',
  component: AttachmentItem,
  decorators: [Story => <div className="d-flex">{Story()}</div>],
} satisfies Meta<typeof AttachmentItem>

export default meta

export const Default = {
  args: {
    onRemove: fn(),
  },
} satisfies StoryObj<typeof AttachmentItem>

export const Suspending = {
  args: {
    onRemove: fn(),
    children: <SuspendingChild />,
  },
} satisfies StoryObj<typeof AttachmentItem>

export const WithPreview = {
  args: {
    onRemove: fn(),
    children: <AttachmentPreviewImage src="https://placecats.com/300/200" alt="example" />,
  },
} satisfies StoryObj<typeof AttachmentItem>

export function DefaultNextToSuspending() {
  return (
    <div className="d-flex flex-row gap-3">
      <AttachmentItem onRemove={fn()} />
      <AttachmentItem onRemove={fn()}>
        <SuspendingChild />
      </AttachmentItem>
    </div>
  )
}

// ---

function SuspendingChild() {
  // eslint-disable-next-line @typescript-eslint/only-throw-error
  throw new Promise(() => {})
  return null
}
