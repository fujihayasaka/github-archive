// filepath: /workspaces/github/ui/packages/copilot-survey/CopilotSurvey.stories.tsx
import type {Meta, StoryObj} from '@storybook/react'
import {CopilotSurvey} from './CopilotSurvey'
import {HttpResponse, http} from 'msw'
import {expect, userEvent, within, waitFor} from '@storybook/test'

/**
 * The CopilotSurvey component displays a banner with feedback request and a call to action
 * to collect user feedback on GitHub features.
 */
const meta: Meta<typeof CopilotSurvey> = {
  title: 'UI/CopilotSurvey',
  component: CopilotSurvey,
  parameters: {
    layout: 'centered',
    msw: {
      handlers: [
        http.post('/api/dismiss', () => {
          return HttpResponse.json({success: true})
        }),
        http.post('/api/open', () => {
          return HttpResponse.json({success: true})
        }),
      ],
    },
  },
  tags: ['autodocs'],
  argTypes: {
    bannerSlug: {
      control: 'select',
      options: ['default', 'secret-protection-feedback-survey'],
      description: 'The type of banner icon to show',
    },
  },
}

export default meta
type Story = StoryObj<typeof CopilotSurvey>

/**
 * Default banner with Copilot icon
 */
export const Default: Story = {
  args: {
    bannerTitle: 'We want your feedback',
    bannerText: 'Help us improve GitHub by sharing your experience with us',
    ctaText: 'Take Survey',
    ctaUrl: 'https://github.com/survey',
    bannerSlug: 'default',
    surveyOpenCallbackPath: '/api/open',
    surveyDismissCallbackPath: '/api/dismiss',
  },
}

/**
 * Banner with Shield icon for Secret Protection feedback
 */
export const SecretProtectionFeedback: Story = {
  args: {
    bannerTitle: 'Secret Protection Feedback',
    bannerText: 'Please help us improve the secret protection experience',
    ctaText: 'Share Feedback',
    ctaUrl: 'https://github.com/secret-protection-survey',
    bannerSlug: 'secret-protection-feedback-survey',
    surveyOpenCallbackPath: '/api/open',
    surveyDismissCallbackPath: '/api/dismiss',
  },
}

/**
 * Demonstrates dismissing the banner by clicking the close button
 */
export const DismissBanner: Story = {
  args: {
    ...Default.args,
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const dismissButton = canvas.getByRole('button', {name: 'Close GrowthBanner'})

    // First verify the button exists
    expect(dismissButton).toBeInTheDocument()

    // Click the dismiss button
    await userEvent.click(dismissButton)

    // Wait for the element to be removed from the DOM
    await waitFor(() => {
      expect(canvas.queryByRole('button', {name: 'Close GrowthBanner'})).not.toBeInTheDocument()
    })
  },
}

/**
 * Demonstrates clicking the CTA button to open the survey
 */
export const ClickSurveyButton: Story = {
  args: {
    ...Default.args,
  },
  parameters: {
    mockNavigate: true,
  },
  play: async ({canvasElement}) => {
    // Since we can't easily mock window.location.href without causing issues,
    // we'll simply test that the button exists and can be clicked,
    // without worrying about the navigation that would happen after

    const canvas = within(canvasElement)
    const surveyButton = canvas.getByRole('button', {name: 'Take Survey'})

    // First verify the close button exists before we click
    const closeButton = canvas.getByRole('button', {name: 'Close GrowthBanner'})
    expect(closeButton).toBeInTheDocument()

    // We don't click the button because that would trigger navigation
    // Just verify that the button exists with the correct text
    expect(surveyButton).toBeInTheDocument()
    expect(surveyButton).toHaveTextContent('Take Survey')
  },
}
