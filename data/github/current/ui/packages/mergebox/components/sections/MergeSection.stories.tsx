import type {Meta, StoryObj} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'

import {MergeSection as MergeSectionComponent} from './merge-section/MergeSection'
import {MergeMethod} from '../../types'
import type {MergeSectionProps} from './merge-section/MergeSection'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {QueryClientProvider} from '@tanstack/react-query'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {mergeBoxMockData} from '../../test-utils/mocks/json-api-response.mock'
import {MergeMethodContextProvider} from '../../contexts/MergeMethodContext'
import {delay, http, HttpResponse} from 'msw'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {Status} from '../../helpers/mergeability-status'
import {expect, userEvent, within} from '@storybook/test'

const enableAutoMergeRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.enableAutoMerge}`
const mergeRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`

const meta: Meta<typeof MergeSectionComponent> = {
  title: 'Pull Requests/mergebox/MergeSection',
  component: MergeSectionComponent,
  decorators: [
    Story => (
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <div style={{maxWidth: '800px'}}>
          <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
            <QueryClientProvider client={queryClient}>
              <MergeMethodContextProvider defaultMergeMethod={MergeMethod.MERGE}>
                <Story />
              </MergeMethodContextProvider>
            </QueryClientProvider>
          </PageDataContextProvider>
        </div>
      </MemoryRouter>
    ),
  ],
  parameters: {
    msw: {
      handlers: [
        http.post(mergeRoute, async () => {
          await delay()
          return HttpResponse.json({error: 'Unable to merge'}, {status: 422})
        }),
        http.post(enableAutoMergeRoute, async () => {
          await delay()
          return HttpResponse.json({error: 'Unable to enable auto-merge'}, {status: 422})
        }),
      ],
    },
  },
}

type Story = StoryObj<typeof MergeSectionComponent>

const nonAPIDataProps = {
  setShouldFocusPrimaryMergeButton: () => {},
  shouldFocusPrimaryMergeButton: true,
}

export const MergeQueueMergeSection: Story = {
  render: () => {
    const mockData = mergeBoxMockData({pullRequestKind: 'withMergeQueueEnabled', mergeRequirementsKind: 'mergeable'})
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      commitAuthorEmail: mockData.mergeRequirements!.commitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: mockData.mergeRequirements!.state,
      numberOfCommits: 1,
      status: Status.InMergeQueue,
      viewerCanEnableAutoMerge: false,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
    }

    return <MergeSectionComponent {...props} />
  },
}

export const MergeQueueAutoMergeSectionWithSoloMergeAllowed: Story = {
  render: () => {
    const mockData = mergeBoxMockData({pullRequestKind: 'withMergeQueueEnabled', mergeRequirementsKind: 'mergeable'})
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      commitAuthorEmail: mockData.mergeRequirements!.commitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody || '',
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: mockData.mergeRequirements!.state,
      numberOfCommits: 1,
      status: Status.InMergeQueue,
      viewerCanEnableAutoMerge: true,
      viewerCanAddToMergeQueueSolo: true,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
    }

    return <MergeSectionComponent {...props} />
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    const selectedMergeMethodButton = await canvas.findByRole('button', {name: 'Merge when ready'})

    await step('Click the "Select merge queue method" icon button', async () => {
      const selectMergeMethodButton = canvas.getByRole('button', {name: 'Select merge queue method'})
      await userEvent.click(selectMergeMethodButton)
    })

    await step(
      'Asserts that 2 merge queue method options exist and clicks the "Queue and force solo merge" option',
      async () => {
        const queueMergeGroupItem = canvas.getByRole('menuitemradio', {name: 'Queue and merge in a group'})
        const queueMergeSoloItem = canvas.getByRole('menuitemradio', {name: 'Queue and force solo merge'})
        expect(queueMergeGroupItem.ariaChecked).toBe('true')
        expect(queueMergeSoloItem.ariaChecked).toBe('false')
        expect(
          canvas.getByText(
            'This pull request will be automatically grouped with other pull requests and merged into master.',
          ),
        ).toBeInTheDocument()
        expect(canvas.getByText('This pull request will be merged into master by itself.')).toBeInTheDocument()
        await userEvent.click(queueMergeSoloItem)

        expect(selectedMergeMethodButton).toHaveTextContent('Queue and force solo merge')
      },
    )
  },
}

export const MergeQueueAutoMergeSectionWithSoloMergeDisallowed: Story = {
  render: () => {
    const mockData = mergeBoxMockData({pullRequestKind: 'withMergeQueueEnabled', mergeRequirementsKind: 'mergeable'})
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      commitAuthorEmail: mockData.mergeRequirements!.commitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody || '',
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: mockData.mergeRequirements!.state,
      numberOfCommits: 1,
      status: Status.InMergeQueue,
      viewerCanEnableAutoMerge: true,
      viewerCanAddToMergeQueueSolo: false,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
    }

    return <MergeSectionComponent {...props} />
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    await canvas.findByRole('button', {name: 'Merge when ready'})
    expect(canvas.queryByRole('button', {name: 'Select merge queue method'})).not.toBeInTheDocument()
  },
}

export const DirectMergeMergeSection: Story = {
  render: () => {
    const mockData = mergeBoxMockData({pullRequestKind: 'withDirectMergeEnabled', mergeRequirementsKind: 'mergeable'})
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      commitAuthorEmail: mockData.mergeRequirements!.commitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: 'MERGEABLE',
      mergeStateStatus: 'CLEAN',
      numberOfCommits: 1,
      status: Status.Mergeable,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
    }
    return <MergeSectionComponent {...props} />
  },
}

export const DirectMergeMergeSectionUnmergeable: Story = {
  render: () => {
    const mockData = mergeBoxMockData({
      pullRequestKind: 'withDirectMergeEnabled',
      mergeRequirementsKind: 'changesRequested',
    })
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      commitAuthorEmail: mockData.mergeRequirements!.commitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'BLOCKED',
      numberOfCommits: 1,
      status: Status.UnableToMerge,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
    }

    return <MergeSectionComponent {...props} />
  },
}

export const DirectMergeOneMergeMethodSection: Story = {
  render: () => {
    const mockData = mergeBoxMockData({
      pullRequestKind: 'onlyOneDirectMergeMethodAllowed',
      mergeRequirementsKind: 'mergeable',
    })
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      commitAuthorEmail: mockData.mergeRequirements!.commitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'CLEAN',
      status: Status.Mergeable,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
    }

    return <MergeSectionComponent {...props} />
  },
}
export const AutoMergeAllowedAndBypassChecked: Story = {
  render: () => {
    const mockData = mergeBoxMockData({
      pullRequestKind: 'withAllowableToBypassAndAutoMerge',
      mergeRequirementsKind: 'unableToMerge',
    })
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements!,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'BLOCKED',
      status: Status.UnableToMerge,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      viewerCanAdminBypassMergeRequirements: true,
    }

    return <MergeSectionComponent {...props} />
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    const bypassCheckbox = canvas.getByText('Merge without waiting for requirements to be met (bypass rules)')
    expect(bypassCheckbox).toBeVisible()
    expect(canvas.getByRole('button', {name: 'Enable auto-merge'})).toBeVisible()
    expect(canvas.queryByRole('button', {name: 'Bypass rules and merge'})).not.toBeInTheDocument()
    await userEvent.click(bypassCheckbox)

    expect(canvas.getByRole('button', {name: 'Bypass rules and merge'})).toBeVisible()
    expect(canvas.queryByRole('button', {name: 'Enable auto-merge'})).not.toBeInTheDocument()

    await userEvent.click(bypassCheckbox)
    expect(canvas.queryByRole('button', {name: 'Bypass rules and merge'})).not.toBeInTheDocument()
    expect(canvas.getByRole('button', {name: 'Enable auto-merge'})).toBeVisible()
  },
}

export const BypassHiddenWhenConfirmingMerge: Story = {
  render: () => {
    const mockData = mergeBoxMockData({
      pullRequestKind: 'withAllowableToBypassAndAutoMerge',
      mergeRequirementsKind: 'unableToMerge',
    })
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements!,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      conflictsCondition: {result: 'PASSED'},
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'BLOCKED',
      status: Status.UnableToMerge,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      viewerCanAdminBypassMergeRequirements: true,
    }

    return <MergeSectionComponent {...props} />
  },
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)

    const bypassCheckbox = canvas.getByText('Merge without waiting for requirements to be met (bypass rules)')
    await userEvent.click(bypassCheckbox)

    expect(canvas.getByRole('button', {name: 'Bypass rules and merge'})).toBeVisible()

    await userEvent.click(canvas.getByRole('button', {name: 'Bypass rules and merge'}))

    expect(
      canvas.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
    ).not.toBeInTheDocument()

    expect(canvas.getByRole('button', {name: 'Confirm bypass rules and merge'})).toBeVisible()
  },
}

export default meta
