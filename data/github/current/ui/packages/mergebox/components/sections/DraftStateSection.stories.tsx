import type {Meta, StoryObj} from '@storybook/react'
import {noop} from '@github-ui/noop'
import {Suspense} from 'react'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {QueryClientProvider} from '@tanstack/react-query'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {delay, http, HttpResponse} from 'msw'
import {userEvent, within, expect} from '@storybook/test'

import {DraftStateSection} from './DraftStateSection'
import type {DraftStateSectionProps} from './DraftStateSection'

const markReadyForReviewMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.markReadyForReview}`

const defaultProps = {
  isDraft: true,
  state: 'OPEN',
  viewerCanUpdate: true,
  refetchQuery: noop,
}

const handlers = {
  success: [
    http.post(markReadyForReviewMutationRoute, () => {
      return HttpResponse.json({
        message: 'Pull request was successfully marked ready for review',
      })
    }),
  ],
  pending: [
    http.post(markReadyForReviewMutationRoute, async () => {
      await delay('infinite')
      return HttpResponse.json({
        message: 'Pull request was successfully marked ready for review',
      })
    }),
  ],
  error: [
    http.post(markReadyForReviewMutationRoute, () => {
      return HttpResponse.json(
        {error: 'Pull request failed to be marked as ready for review'},
        {
          status: 403,
        },
      )
    }),
  ],
}

const meta: Meta = {
  title: 'Pull Requests/mergebox/DraftStateSection',
  component: DraftStateSection,
  decorators: [
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <QueryClientProvider client={queryClient}>
            <div style={{maxWidth: '600px'}}>
              <Suspense>
                <Story />
              </Suspense>
            </div>
          </QueryClientProvider>
        </PageDataContextProvider>
      )
    },
  ],
  args: defaultProps,
}

type Story = StoryObj<DraftStateSectionProps>

const Template: Story = {
  render: args => {
    const props = {
      ...defaultProps,
      ...args,
    }

    return <DraftStateSection {...props} />
  },
}

export const SuccessWhenMarkReadyForReview: typeof Template = {
  ...Template,
  parameters: {
    msw: handlers.success,
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    await step('User can view button to mark a pull request as ready for review', async () => {
      expect(await canvas.findByRole('button', {name: 'Ready for review'})).toBeVisible()
    })
  },
}

export const PendingWhenMarkReadyForReview: typeof Template = {
  ...Template,
  parameters: {
    msw: handlers.pending,
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    await step('User marking a pull request as ready for review moves button to pending status', async () => {
      const button = await canvas.findByRole('button', {name: 'Ready for review'})

      await userEvent.click(button)

      expect(button).toHaveTextContent(/Marking ready for review.../)
    })
  },
}

export const ErrorWhenMarkReadyForReview: typeof Template = {
  ...Template,
  parameters: {
    msw: handlers.error,
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    await step('User marking a pull request as ready for review shows error message on failure', async () => {
      const button = await canvas.findByRole('button', {name: 'Ready for review'})

      await userEvent.click(button)

      expect(await canvas.findByText('Pull request failed to be marked as ready for review')).toBeVisible()
    })
  },
}

export default meta
