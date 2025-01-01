import type {Meta, StoryObj} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'

import {ConflictsSection, type ConflictsSectionProps} from './ConflictsSection'
import {AppContext} from '@github-ui/react-core/app-context'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {
  conflictsSectionCleanMergeState,
  conflictsSectionComplexConflictsMergeState,
  conflictsSectionPendingMergeState,
  conflictsSectionStandardConflictsMergeState,
} from '../../test-utils/mocks/conflicts-condition-mock'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {QueryClientProvider} from '@tanstack/react-query'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {http, HttpResponse} from 'msw'

const conflictsSectionDefaultProps: ConflictsSectionProps = {
  ...conflictsSectionCleanMergeState,
  baseRefName: 'main',
  headRefOid: 'abc123',
  resourcePath: '/octocat/Hello-World/pull/123',
  viewerCanUpdateBranch: true,
  viewerLogin: 'monalisa',
  canUserPushToBase: true,
}

const updatePullRequestBranchRoute = `${BASE_PAGE_DATA_URL}/page_data/update_pull_request_branch`
const orchestrationUrl = 'https://github.com/orchestration/1234'

const meta: Meta<ConflictsSectionProps> = {
  title: 'Pull Requests/mergebox/ConflictsSection',
  component: ConflictsSection,
  decorators: [
    Story => (
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <AppContext.Provider
          value={{
            routes: [jsonRoute({path: '/a', Component: () => null})],
          }}
        >
          <div style={{maxWidth: '600px'}}>
            <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
              <QueryClientProvider client={queryClient}>
                <Story />
              </QueryClientProvider>
            </PageDataContextProvider>
          </div>
        </AppContext.Provider>
      </MemoryRouter>
    ),
  ],
  parameters: {
    msw: {
      handlers: [
        http.post(updatePullRequestBranchRoute, () => {
          return HttpResponse.json({orchestration: {url: orchestrationUrl}}, {status: 200})
        }),
        http.get(orchestrationUrl, () => {
          return HttpResponse.json({orchestration: {}}, {status: 200})
        }),
      ],
    },
  },
  args: conflictsSectionDefaultProps,
}

type Story = StoryObj<ConflictsSectionProps>

export const ConflictsSectionCleanStory: Story = {
  render: args => {
    const props = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionPendingStory: Story = {
  render: args => {
    const props = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionPendingMergeState,
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionHasConflictsStory: Story = {
  render: args => {
    const props = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionStandardConflictsMergeState,
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionComplexConflictsStory: Story = {
  render: args => {
    const props = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionComplexConflictsMergeState,
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionCleanStoryUpdateBranchError: Story = {
  parameters: {
    msw: {
      handlers: [
        http.post(updatePullRequestBranchRoute, () => {
          return HttpResponse.json({orchestration: {url: orchestrationUrl}}, {status: 200})
        }),
        http.get(orchestrationUrl, () => {
          return HttpResponse.json({orchestration: {error_message: 'Trouble updating branch'}}, {status: 200})
        }),
      ],
    },
  },
  render: args => {
    const props = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
    }
    return <ConflictsSection {...props} />
  },
}

export const ConflictsSectionCleanStoryUpdateBranchRequestFailed: Story = {
  parameters: {
    msw: {
      handlers: [
        http.post(updatePullRequestBranchRoute, () => {
          return HttpResponse.json({error: 'Branch update already in progress'}, {status: 422})
        }),
      ],
    },
  },
  render: args => {
    const props = {
      ...conflictsSectionDefaultProps,
      ...args,
      ...conflictsSectionCleanMergeState,
    }
    return <ConflictsSection {...props} />
  },
}

export default meta
