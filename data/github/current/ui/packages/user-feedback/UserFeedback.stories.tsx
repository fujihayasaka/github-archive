import {useRef} from 'react'
import type {Meta, StoryObj} from '@storybook/react'
import {type FeedbackRef, UserFeedback, type UserFeedbackProps} from './UserFeedback'
import {Button, ActionMenu, ActionList, IconButton} from '@primer/react'
import {KebabHorizontalIcon, ThumbsupIcon, ThumbsdownIcon, TrashIcon, HeartIcon} from '@primer/octicons-react'
import {noop} from '@github-ui/noop'

const optionSet1 = [
  {name: 'Garbage', value: 0, icon: <TrashIcon />, color: 'veryDissatisfied' as const},
  {name: 'Meh', value: 1, icon: <ThumbsdownIcon />, color: 'dissatisfied' as const},
  {name: 'Like It', value: 2, icon: <ThumbsupIcon />, color: 'satisfied' as const},
  {name: 'Love It', value: 3, icon: <HeartIcon />, color: 'verySatisfied' as const},
]

const optionSet2 = [
  {name: 'Bad', value: 'BAD_VALUE' as const, icon: <ThumbsdownIcon />, color: 'bad' as const},
  {name: 'Good', value: 'GOOD_VALUE' as const, icon: <ThumbsupIcon />, color: 'good' as const},
]

const optionSets = {optionSet1, optionSet2}

type Rating = (typeof optionSets)[keyof typeof optionSets][number]['value']
type Story = StoryObj<UserFeedbackProps<Rating>>

const meta = {
  title: 'Recipes/UserFeedback',
  component: UserFeedback,
  parameters: {
    layout: 'centered',
    controls: {expanded: true, sort: 'alpha'},
  },
  args: {
    options: optionSet1,
    onSubmit: () => Promise.resolve([]),
    onClose: noop,
  },
  argTypes: {
    title: {
      description: 'Optional title for the dialog.',
      type: 'string',
      table: {defaultValue: {summary: 'Give feedback'}},
      control: {type: 'text'},
    },
    options: {
      description: 'The ratings options for the feedback dialog.',
      type: {
        name: 'array',
        required: true,
        value: {name: 'other', value: 'Array<RatingOption<Rating>>'},
      },
      table: {type: {summary: 'Array<RatingOption<Rating>>'}},
      options: Object.keys(optionSets),
      mapping: optionSets,
      control: {
        type: 'select',
        labels: {
          optionSet1: 'Example (Garbage/Meh/Like/Love)',
          optionSet2: 'Example (Bad/Good)',
        },
      },
    },
    onSubmit: {
      description:
        'Called when the user submits the form. Returns an array of error strings which will be displayed to the user.',
      type: {name: 'function', required: true},
      table: {type: {summary: '(rating: Rating, text: string) => Promise<string[]>'}},
    },
    onClose: {
      description: 'Optional callback called when the dialog closes.',
      table: {type: {summary: '() => void'}},
    },
  },
} satisfies Meta<UserFeedbackProps<Rating>>

export default meta

const sendFeedbackToServer = async (_rating: unknown, _text: string): Promise<{ok: boolean}> => {
  return Promise.resolve({ok: true})
}

export const WithButton: Story = {
  render: function WithButtonStory({title, options}: UserFeedbackProps<Rating>) {
    const onSubmit = async (rating: Rating | null, text: string): Promise<string[]> => {
      try {
        const resp = await sendFeedbackToServer(rating, text)
        if (resp.ok) {
          alert(`Feedback submitted - Rating: ${rating}, Text: ${text}`)
        } else {
          return ['An error occurred while submitting your feedback.']
        }
      } catch {
        return ['An error occurred while submitting your feedback.']
      }

      return []
    }

    const feedbackRef = useRef<FeedbackRef<Rating>>(null)
    return (
      <>
        <Button onClick={() => feedbackRef.current?.openDialog()}>Give Feedback</Button>
        <UserFeedback ref={feedbackRef} title={title} options={options} onSubmit={onSubmit} />
      </>
    )
  },
}

export const WithMenuItem: Story = {
  render: function WithMenuItemStory({title, options}: UserFeedbackProps<Rating>) {
    const onSubmit = async (rating: Rating | null, text: string): Promise<string[]> => {
      try {
        const resp = await sendFeedbackToServer(rating, text)
        if (resp.ok) {
          alert(`Feedback submitted - Rating: ${rating}, Text: ${text}`)
        } else {
          return ['An error occurred while submitting your feedback.']
        }
      } catch {
        return ['An error occurred while submitting your feedback.']
      }

      return []
    }

    const feedbackRef = useRef<FeedbackRef<Rating>>(null)

    return (
      <>
        <ActionMenu>
          <ActionMenu.Anchor>
            <IconButton icon={KebabHorizontalIcon} aria-label="Open menu" />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay>
            <ActionList>
              <ActionList.Item onSelect={() => feedbackRef.current?.openDialog()}>Give Feedback</ActionList.Item>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
        <UserFeedback ref={feedbackRef} title={title} options={options} onSubmit={onSubmit} />
      </>
    )
  },
}

export const WithPreSelectedRating: Story = {
  name: 'With Pre-Selected Rating',
  render: function WithButtonStory({title, options}: UserFeedbackProps<Rating>) {
    const onSubmit = async (rating: Rating | null, text: string): Promise<string[]> => {
      try {
        const resp = await sendFeedbackToServer(rating, text)
        if (resp.ok) {
          alert(`Feedback submitted - Rating: ${rating}, Text: ${text}`)
        } else {
          return ['An error occurred while submitting your feedback.']
        }
      } catch {
        return ['An error occurred while submitting your feedback.']
      }

      return []
    }

    const feedbackRef = useRef<FeedbackRef<Rating>>(null)
    return (
      <>
        <Button onClick={() => feedbackRef.current?.openDialog(options[0]!.value)}>Give Feedback</Button>
        <UserFeedback ref={feedbackRef} title={title} options={options} onSubmit={onSubmit} />
      </>
    )
  },
}

export const WithSubmissionErrors: Story = {
  render: function WithButtonStory({title, options}: UserFeedbackProps<Rating>) {
    const onSubmit = async (rating: Rating | null, text: string): Promise<string[]> => {
      // Any strings returned from this function will be displayed to the user as errors.
      // For example, if the user doesn't select a rating, you can return an error message.

      const errors = []
      if (rating == null) {
        errors.push('Please select a rating.')
      }

      if (text.length === 0) {
        errors.push('Please provide text feedback.')
      }

      // return validation errors before trying to send feedback to the server
      if (errors.length > 0) {
        return errors
      }

      try {
        const resp = await Promise.resolve({ok: false}) // await sendFeedbackToServer(rating, text)
        if (resp.ok) {
          alert(`Feedback submitted - Rating: ${rating}, Text: ${text}`)
        } else {
          errors.push('An error occurred while submitting your feedback.')
        }
      } catch {
        errors.push('An error occurred while submitting your feedback.')
      }

      return errors
    }

    const feedbackRef = useRef<FeedbackRef<Rating>>(null)

    return (
      <>
        <Button onClick={() => feedbackRef.current?.openDialog()}>Give Feedback</Button>
        <UserFeedback ref={feedbackRef} title={title} options={options} onSubmit={onSubmit} />
      </>
    )
  },
}
