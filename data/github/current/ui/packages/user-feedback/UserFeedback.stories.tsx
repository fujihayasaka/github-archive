import {useRef} from 'react'
import type {Meta, StoryObj} from '@storybook/react'
import type {FeedbackRef} from './UserFeedback'
import {UserFeedback} from './UserFeedback'
import {Button, ActionMenu, ActionList, IconButton} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'

const meta: Meta<typeof UserFeedback> = {
  title: 'Recipes/UserFeedback/Examples',
  component: UserFeedback,
}

export default meta

type Story = StoryObj<typeof UserFeedback>

export const WithButton: Story = {
  render: function WithButtonStory() {
    const feedbackRef = useRef<FeedbackRef>(null)

    return (
      <>
        <Button onClick={() => feedbackRef.current?.openDialog()}>Feedback</Button>
        <UserFeedback ref={feedbackRef} />
      </>
    )
  },
}

export const WithMenuItem: Story = {
  render: function WithMenuItemStory() {
    const feedbackRef = useRef<FeedbackRef>(null)

    return (
      <>
        <ActionMenu>
          <ActionMenu.Anchor>
            <IconButton icon={KebabHorizontalIcon} aria-label="Open menu" />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay>
            <ActionList>
              <ActionList.Item onSelect={() => feedbackRef.current?.openDialog()}>Provide Feedback</ActionList.Item>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
        <UserFeedback ref={feedbackRef} />
      </>
    )
  },
}
