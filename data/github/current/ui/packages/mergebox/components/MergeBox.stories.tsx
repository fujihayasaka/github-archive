import type {ArgTypes, Meta, StoryObj} from '@storybook/react'
import {delay, http, HttpResponse} from 'msw'
import {MemoryRouter} from 'react-router-dom'
import {AppContext} from '@github-ui/react-core/app-context'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {QueryClientProvider} from '@tanstack/react-query'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {MergeBoxTestComponent as MergeBoxComponent} from '../test-utils/MergeBoxTestComponent'
import {mergeBoxMockData} from '../test-utils/mocks/json-api-response.mock'

import {
  checksSectionPendingState,
  checksSectionPendingWithFailureState,
  checksSectionPassingState,
  checksSectionSomeFailedState,
  checksSectionFailedState,
  checksSectionNonRequiredChecksFailingState,
  checksSectionNonRequiredChecksPassingSkippedNeutralState,
  checksSectionWithMultipleOfEveryState,
} from '../test-utils/mocks/checks-section-mocks'

const statusChecksPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.statusChecks}`
const mergeBoxPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.mergeBox}?merge_method=MERGE&bypass_requirements=false`

const argTypes: ArgTypes = {
  hideIcon: {control: {type: 'boolean'}},
}

const meta: Meta<typeof MergeBoxComponent> = {
  title: 'Pull Requests/mergebox/MergeBox',
  component: MergeBoxComponent,
  args: {
    hideIcon: false,
  },
  argTypes,
  decorators: [
    Story => {
      // Resets the Tanstack Query Client Cache between stroies to ensure that we don't use stale data.
      queryClient.clear()

      return (
        <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
          <AppContext.Provider
            value={{
              routes: [jsonRoute({path: '/a', Component: () => null})],
            }}
          >
            <QueryClientProvider client={queryClient}>
              <div style={{maxWidth: '1000px', marginLeft: '50px'}}>
                <Story />
              </div>
            </QueryClientProvider>
          </AppContext.Provider>
        </MemoryRouter>
      )
    },
  ],
}

type Story = StoryObj<typeof MergeBoxComponent>

export const readyToMerge: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(
            mergeBoxMockData({pullRequestKind: 'withDirectMergeEnabled', mergeRequirementsKind: 'mergeable'}),
          )
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const reviewsRequiredAndApprovingReviews: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(
            mergeBoxMockData({
              pullRequestKind: 'default',
              mergeRequirementsKind: 'reviewsRequiredAndApprovingReviews',
            }),
          )
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const changesRequested: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(
            mergeBoxMockData({pullRequestKind: 'default', mergeRequirementsKind: 'changesRequested'}),
          )
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const pendingGitMergeStatus: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(
            mergeBoxMockData({pullRequestKind: 'unknownGitMergeStatus', mergeRequirementsKind: 'unknownNoConflicts'}),
          )
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const noReviewsAndFailedChecksHasConflicts: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(
            mergeBoxMockData({pullRequestKind: 'noReviewsConflicts', mergeRequirementsKind: 'mergeConflicts'}),
          )
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionFailedState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const closed: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'closedWithUserActionsAllowed'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const merged: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'mergedWithUserActionsAllowed'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const queued: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'isInMergeQueue'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const mergeableWithFailingNonRequiredChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(
            mergeBoxMockData({pullRequestKind: 'withApprovingReviews', mergeRequirementsKind: 'mergeable'}),
          )
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionNonRequiredChecksFailingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const mergeableWithPassingNonRequiredChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(
            mergeBoxMockData({pullRequestKind: 'withApprovingReviews', mergeRequirementsKind: 'mergeable'}),
          )
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionNonRequiredChecksPassingSkippedNeutralState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const pendingAllChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPendingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const failingAndPendingChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPendingWithFailureState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const passingAllChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionPassingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const failingSomeChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionSomeFailedState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const failingAllChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(checksSectionFailedState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const failedToLoadChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, () => {
          return HttpResponse.json(null, {status: 403})
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const loadingChecks: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, async () => {
          await delay('infinite')
          return HttpResponse.json(checksSectionPendingState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export const withMultipleChecksOfEverykind: Story = {
  argTypes,
  parameters: {
    msw: {
      handlers: [
        http.get(mergeBoxPageDataRoute, () => {
          return HttpResponse.json(mergeBoxMockData({pullRequestKind: 'default'}))
        }),
        http.get(statusChecksPageDataRoute, async () => {
          return HttpResponse.json(checksSectionWithMultipleOfEveryState)
        }),
      ],
    },
  },
  render: args => <MergeBoxComponent {...args} />,
}

export default meta
