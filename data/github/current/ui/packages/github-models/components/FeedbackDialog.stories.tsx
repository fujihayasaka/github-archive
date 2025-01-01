import {useEffect, useRef, useState} from 'react'
import {http, HttpResponse} from 'msw'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {modelFeedbackPath} from '@github-ui/paths'
import {FeedbackDialog, type FeedbackDialogProps} from './FeedbackDialog'
import {parametersConfig} from '../utils/story-utils'
import {mockShowModelPayload} from '../routes/show/components/__tests__/mocks'
import {mockModel} from '../routes/playground/__tests__/mocks'

const meta: Meta = {
  title: 'Apps/GitHub Models/FeedbackDialog',
  component: FeedbackDialog,
  args: {
    isFeedbackDialogOpen: true,
    isNegativePreSelected: false,
    modelName: mockModel.name,
  },
  parameters: {
    ...parametersConfig,
    a11y: {
      config: {
        rules: [
          {id: 'color-contrast', enabled: false}, // Test fails due to the 'Close' Tooltip from Primer
        ],
      },
    },
    msw: {handlers: [http.post(modelFeedbackPath(mockModel), () => HttpResponse.json({}, {status: 200}))]},
  },
  decorators: [
    storyWrapper({
      routePayload: mockShowModelPayload(),
    }),
  ],
} satisfies Meta<FeedbackDialogProps>

export default meta

function StoryComponent(props: FeedbackDialogProps) {
  const returnFocusRef = useRef(null)
  const [isOpen, setIsOpen] = useState(props.isFeedbackDialogOpen)

  useEffect(() => {
    setIsOpen(props.isFeedbackDialogOpen)
  }, [props.isFeedbackDialogOpen])

  return (
    <>
      <button ref={returnFocusRef} onClick={() => setIsOpen(true)}>
        Open dialog
      </button>
      <FeedbackDialog
        {...props}
        returnFocusRef={returnFocusRef}
        isFeedbackDialogOpen={isOpen}
        setIsFeedbackDialogOpen={() => setIsOpen(!isOpen)}
      />
    </>
  )
}

export const Example: StoryObj<FeedbackDialogProps> = {
  render: args => <StoryComponent {...args} />,
}
