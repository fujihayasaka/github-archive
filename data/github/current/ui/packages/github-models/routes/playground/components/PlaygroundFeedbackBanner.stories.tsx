import type {Meta, StoryObj} from '@storybook/react'
import {PlaygroundFeedbackBanner} from './PlaygroundFeedbackBanner'
import {parametersConfig} from '../../../utils/story-utils'

const meta: Meta = {
  title: 'Apps/GitHub Models/PlaygroundFeedbackBanner',
  component: PlaygroundFeedbackBanner,
  parameters: parametersConfig,
}

export default meta

export const Example: StoryObj = {
  render: () => <PlaygroundFeedbackBanner />,
}
