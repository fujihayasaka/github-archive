import type {Meta, StoryObj} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'
import {shouldInteractionPlay} from '@github-ui/storybook'

import {MergeSection as MergeSectionComponent} from './merge-section/MergeSection'
import {MergeMethod} from '../../types'
import type {MergeSectionProps} from './merge-section/MergeSection'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {mergeBoxMockData} from '../../test-utils/mocks/json-api-response.mock'
import {MergeMethodContextProvider} from '../../contexts/MergeMethodContext'
import {delay, http, HttpResponse} from 'msw'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {Status} from '../../helpers/mergeability-status'
import {expect, userEvent, within} from '@storybook/test'
import {defaultMergeInstructionsApiResponse} from '../../test-utils/mocks/merge-instructions-mock'

const enableAutoMergeRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.enableAutoMerge}`
const mergeRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
const mergeInstructionsPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.mergeInstructions}`
const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`

const meta: Meta<typeof MergeSectionComponent> = {
  title: 'Pull Requests/Merge Box/MergeSection',
  component: MergeSectionComponent,
  decorators: [
    Story => (
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <div style={{maxWidth: '800px'}}>
          <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
            <MergeMethodContextProvider defaultMergeMethod={MergeMethod.MERGE}>
              <Story />
            </MergeMethodContextProvider>
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
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'ALL_PASSED',
      mergeRequirementsState: mockData.mergeRequirements!.state,
      numberOfCommits: 1,
      status: Status.InMergeQueue,
      viewerCanEnableAutoMerge: false,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      possibleCommitAuthorEmails: [],
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
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody || '',
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'ALL_PASSED',
      mergeRequirementsState: mockData.mergeRequirements!.state,
      numberOfCommits: 1,
      status: Status.InMergeQueue,
      viewerCanEnableAutoMerge: true,
      viewerCanAddToMergeQueueSolo: true,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      possibleCommitAuthorEmails: [],
    }

    return <MergeSectionComponent {...props} />
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

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
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody || '',
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'ALL_PASSED',
      mergeRequirementsState: mockData.mergeRequirements!.state,
      numberOfCommits: 1,
      status: Status.InMergeQueue,
      viewerCanEnableAutoMerge: true,
      viewerCanAddToMergeQueueSolo: false,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      possibleCommitAuthorEmails: [],
    }

    return <MergeSectionComponent {...props} />
  },
  play: async ({canvasElement}) => {
    if (!shouldInteractionPlay()) return

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
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'ALL_PASSED',
      mergeRequirementsState: 'MERGEABLE',
      mergeStateStatus: 'CLEAN',
      numberOfCommits: 1,
      status: Status.Mergeable,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      possibleCommitAuthorEmails: [],
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
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'SOME_FAILED',
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'BLOCKED',
      numberOfCommits: 1,
      status: Status.UnableToMerge,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      possibleCommitAuthorEmails: [],
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
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'ALL_PASSED',
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'CLEAN',
      status: Status.Mergeable,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      possibleCommitAuthorEmails: [],
    }

    return <MergeSectionComponent {...props} />
  },
}

export const DirectMergeWithMultipleCommitAuthorEmails: Story = {
  render: () => {
    const mockData = mergeBoxMockData({
      pullRequestKind: 'onlyOneDirectMergeMethodAllowed',
      mergeRequirementsKind: 'mergeable',
    })
    const props: MergeSectionProps = {
      ...mockData.mergeRequirements,
      ...mockData.pullRequest,
      ...nonAPIDataProps,
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      commitMessageBody: null,
      commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'ALL_PASSED',
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'CLEAN',
      status: Status.Mergeable,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      possibleCommitAuthorEmails: ['mona@github.com', 'octocat@github.com', 'test@github'],
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
      defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
      conflictsCondition: {result: 'PASSED'},
      mergeBoxRollupStatus: 'SOME_FAILED',
      mergeRequirementsState: mockData.mergeRequirements!.state,
      mergeStateStatus: 'BLOCKED',
      status: Status.UnableToMerge,
      canUserPushToBase: true,
      helpUrl: 'https://docs.github.com',
      viewerCanAdminBypassMergeRequirements: true,
      possibleCommitAuthorEmails: [],
    }

    return <MergeSectionComponent {...props} />
  },
  play: async ({canvasElement}) => {
    if (!shouldInteractionPlay()) return

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

const MergeableDirectMergePullRequestProps = () => {
  const mockData = mergeBoxMockData({pullRequestKind: 'withDirectMergeEnabled', mergeRequirementsKind: 'mergeable'})
  const props: MergeSectionProps = {
    ...mockData.mergeRequirements,
    ...mockData.pullRequest,
    ...nonAPIDataProps,
    defaultCommitAuthorEmail: mockData.mergeRequirements!.defaultCommitAuthorEmail,
    commitMessageBody: mockData.mergeRequirements!.commitMessageBody,
    commitMessageHeadline: mockData.mergeRequirements!.commitMessageHeadline,
    conflictsCondition: {result: 'PASSED'},
    mergeBoxRollupStatus: 'ALL_PASSED',
    mergeRequirementsState: 'MERGEABLE',
    mergeStateStatus: 'CLEAN',
    numberOfCommits: 1,
    status: Status.Mergeable,
    canUserPushToBase: true,
    helpUrl: 'https://docs.github.com',
    possibleCommitAuthorEmails: [],
  }

  return props
}

export const MergablePullRequest: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(mergeInstructionsPageDataRoute, () => {
          return HttpResponse.json(defaultMergeInstructionsApiResponse)
        }),
      ],
    },
  },
  render: () => <MergeSectionComponent {...MergeableDirectMergePullRequestProps()} />,
}

export const MergablePullRequestWithSuccessfulDirectMerge: Story = {
  parameters: {
    msw: [
      http.post(mergeMutationRoute, () =>
        HttpResponse.json({
          message: 'Pull request is merged.',
        }),
      ),
    ],
  },
  render: () => <MergeSectionComponent {...MergeableDirectMergePullRequestProps()} />,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

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

export const MergablePullRequestWithFailedDirectMerge: Story = {
  parameters: {
    msw: [
      http.post(mergeMutationRoute, () =>
        HttpResponse.json({error: 'We couldn’t merge this pull request.'}, {status: 422}),
      ),
    ],
  },
  render: () => <MergeSectionComponent {...MergeableDirectMergePullRequestProps()} />,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('User merging a pull request sees error message on failure', async () => {
      const mergeButton = await canvas.findByRole('button', {name: 'Merge pull request'})

      await userEvent.click(mergeButton)

      const confirmMergeButton = await canvas.findByRole('button', {name: 'Confirm merge'})

      await userEvent.click(confirmMergeButton)

      expect(await canvas.findAllByText('We couldn’t merge this pull request.')).toHaveLength(2)
    })
  },
}

export const MergablePullRequestWithPendingDirectMerge: Story = {
  parameters: {
    msw: [
      http.post(mergeMutationRoute, async () => {
        await delay('infinite')
      }),
    ],
  },
  render: () => <MergeSectionComponent {...MergeableDirectMergePullRequestProps()} />,
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('User merging a pull request sees pending button state while waiting for merge to finish', async () => {
      const mergeButton = await canvas.findByRole('button', {name: 'Merge pull request'})

      await userEvent.click(mergeButton)

      const confirmMergeButton = await canvas.findByRole('button', {name: 'Confirm merge'})

      expect(confirmMergeButton).not.toHaveAccessibleDescription()

      await userEvent.click(confirmMergeButton)

      expect(confirmMergeButton).toHaveAccessibleDescription('Merging...')
    })
  },
}

export default meta
