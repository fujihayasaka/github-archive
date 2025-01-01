import type {Meta, StoryObj} from '@storybook/react'
import {Suspense} from 'react'
import {MemoryRouter} from 'react-router-dom'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {delay, http, HttpResponse} from 'msw'

import {ChecksSection, type ChecksSectionProps} from './ChecksSection'
import {
  checksSectionPendingState,
  checksSectionPassingState,
  checksSectionFailedState,
  checksSectionPendingWithFailureState,
  checksSectionSomeFailedState,
  checksSectionPendingAndWaitingState,
  checksSectionPendingApproval,
  checksSectionPendingApprovalWithChecks,
  checksSectionPendingWithFailureStateAndCopilot,
} from '../../test-utils/mocks/checks-section-mocks'
import {noop} from '@github-ui/noop'

const meta: Meta<typeof ChecksSection> = {
  title: 'Pull Requests/Merge Box/ChecksSection',
  component: ChecksSection,
  decorators: [
    Story => {
      return (
        <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
          <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
            <div style={{maxWidth: '600px'}}>
              <Suspense>
                <Story />
              </Suspense>
            </div>
          </PageDataContextProvider>
        </MemoryRouter>
      )
    },
  ],
}

type Story = StoryObj<typeof ChecksSection>

const defaultProps: ChecksSectionProps = {
  pullRequestId: 'pullRequest123',
  pullRequestHeadSha: 'mock-head-sha',
  focusPrimaryMergeButton: noop,
  sectionStatus: 'PENDING',
  shouldRender: true,
}
const conflictProps: ChecksSectionProps = {
  pullRequestId: 'pullRequest123',
  pullRequestHeadSha: 'mock-head-sha',
  focusPrimaryMergeButton: noop,
  sectionStatus: 'PENDING_CONFLICTS',
  shouldRender: true,
}
const statusChecksPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.statusChecks}`
const runActionRequiredWorkflowsRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.runActionRequiredWorkflows}`
const argTypes = {
  pullRequestId: {
    table: {
      disable: true,
    },
  },
}

export const pending: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPendingState)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...defaultProps} />,
}

export const pendingWithFailure: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPendingWithFailureState)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...{...defaultProps, sectionStatus: 'SOME_FAILED'}} />,
}

export const pendingApproval: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json({
            ...checksSectionPendingApproval,
          })
        }),
        http.post(runActionRequiredWorkflowsRoute, async () => {
          await delay(1000)
          return HttpResponse.json(
            {
              error: 'Unable to run required workflows',
            },
            {status: 422},
          )
        }),
      ],
    },
  },
  render: () => <ChecksSection {...{...defaultProps, sectionStatus: 'PENDING_APPROVAL'}} />,
}

export const pendingApprovalWithChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json({
            ...checksSectionPendingApprovalWithChecks,
          })
        }),
        http.post(runActionRequiredWorkflowsRoute, async () => {
          await delay(1000)
          return HttpResponse.json(
            {
              error: 'Unable to run required workflows',
            },
            {status: 422},
          )
        }),
      ],
    },
  },
  render: () => <ChecksSection {...{...defaultProps, sectionStatus: 'PENDING_APPROVAL'}} />,
}

export const passing: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...{...defaultProps, sectionStatus: 'PASSED'}} />,
}

export const failing: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionFailedState)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...{...defaultProps, sectionStatus: 'FAILED'}} />,
}

export const someFailing: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionSomeFailedState)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...{...defaultProps, sectionStatus: 'SOME_FAILED'}} />,
}

export const someWaitingForStatusToBeReported: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPendingAndWaitingState)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...{...defaultProps, sectionStatus: 'PENDING'}} />,
}

export const awaitingConflictResolution: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPendingState)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...conflictProps} />,
}

export const failingWithCopilot: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPendingWithFailureStateAndCopilot)
        }),
      ],
    },
  },
  render: () => <ChecksSection {...defaultProps} />,
}

export default meta
