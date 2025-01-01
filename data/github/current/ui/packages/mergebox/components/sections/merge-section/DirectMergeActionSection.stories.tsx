import type {Meta, StoryObj} from '@storybook/react'
import {Suspense} from 'react'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {noop} from '@github-ui/noop'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {QueryClientProvider} from '@tanstack/react-query'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {delay, http, HttpResponse} from 'msw'
import {userEvent, within, expect} from '@storybook/test'

import type {Props as DirectMergeActionsSectionProps} from './DirectMergeActionsSection'
import {DirectMergeActionsSection} from './DirectMergeActionsSection'
import {defaultPullRequest} from '../../../test-utils/mocks/json-api-response.mock'
import {defaultMergeInstructionsApiResponse} from '../../../test-utils/mocks/merge-instructions-mock'

const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
const mergeInstructionsPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.mergeInstructions}`

const defaultProps = {
  ...defaultPullRequest,
  canUserPushToBase: true,
  shouldFocusPrimaryMergeButton: false,
  setShouldFocusPrimaryMergeButton: noop,
  commitAuthor: 'monalisa',
  commitMessageBody: 'default message body',
  commitMessageHeadline: 'default commit title',
  mergeRequirementsState: 'MERGEABLE',
  mergeable: true,
  conflictsCondition: {result: 'PASSED'},
  isAdminBypassToggleVisible: false,
  isAdminBypassToggleChecked: false,
  onIsConfirmingSelectedMerge: noop,
}

const meta: Meta = {
  title: 'Pull Requests/mergebox/MergeSection/DirectMergeActionsSection',
  component: DirectMergeActionsSection,
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

type Story = StoryObj<DirectMergeActionsSectionProps>

const Template: Story = {
  argTypes: {
    setShouldFocusPrimaryMergeButton: {
      table: {
        disable: true,
      },
    },
  },
  render: args => {
    const props = {
      ...defaultProps,
      ...args,
    }

    return <DirectMergeActionsSection {...props} />
  },
}

const handlers = {
  success: [
    http.post(mergeMutationRoute, () => {
      return HttpResponse.json({
        message: 'Pull request is merged.',
      })
    }),
  ],
  pending: [
    http.post(mergeMutationRoute, async () => {
      await delay('infinite')
      return HttpResponse.json({
        message: 'Pull request is merged.',
      })
    }),
  ],
  error: [
    http.post(mergeMutationRoute, () => {
      return HttpResponse.json(
        {error: 'We couldn’t merge this pull request.'},
        {
          status: 422,
        },
      )
    }),
  ],
}

export const MergablePullRequestWithSuccessfulDirectMerge: typeof Template = {
  ...Template,
  parameters: {
    msw: handlers.success,
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    await step('User merging a pull request does not see error message on success', async () => {
      const mergeButton = await canvas.findByRole('button', {name: 'Merge pull request'})

      await userEvent.click(mergeButton)

      const confirmMergeButton = await canvas.findByRole('button', {name: 'Confirm merge'})

      await userEvent.click(confirmMergeButton)

      expect(await canvas.queryByText('We couldn’t merge this pull request.')).toBeNull()
    })
  },
}

export const MergablePullRequest: typeof Template = {
  ...Template,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeInstructionsPageDataRoute, () => {
          return HttpResponse.json(defaultMergeInstructionsApiResponse)
        }),
      ],
    },
  },
}

export const MergablePullRequestWithFailedDirectMerge: typeof Template = {
  ...Template,
  parameters: {
    msw: handlers.error,
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    await step('User merging a pull request sees error message on failure', async () => {
      const mergeButton = await canvas.findByRole('button', {name: 'Merge pull request'})

      await userEvent.click(mergeButton)

      const confirmMergeButton = await canvas.findByRole('button', {name: 'Confirm merge'})

      await userEvent.click(confirmMergeButton)

      expect(await canvas.findByText('We couldn’t merge this pull request.')).toBeVisible()
    })
  },
}

export const MergablePullRequestWithPendingDirectMerge: typeof Template = {
  ...Template,
  parameters: {
    msw: handlers.pending,
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    await step('User merging a pull request sees pending button state while waiting for merge to finish', async () => {
      const mergeButton = await canvas.findByRole('button', {name: 'Merge pull request'})

      await userEvent.click(mergeButton)

      const confirmMergeButton = await canvas.findByRole('button', {name: 'Confirm merge'})

      await userEvent.click(confirmMergeButton)

      expect(confirmMergeButton).toHaveTextContent('Merging...')
    })
  },
}

export default meta
