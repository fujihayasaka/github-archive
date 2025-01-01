import type {Meta, StoryObj} from '@storybook/react'
import {MemoryRouter} from 'react-router-dom'

import {MergeQueueSection, type Props} from './MergeQueueSection'
import type {MergeQueueEntryState} from '../../../types'
import {noop} from '@github-ui/noop'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {delay, http, HttpResponse} from 'msw'

const disableArgs = {
  mergeQueue: {
    table: {
      disable: true,
    },
  },
  mergeQueueEntry: {
    table: {
      disable: true,
    },
  },
  focusPrimaryMergeButton: {
    table: {
      disable: true,
    },
  },
  viewerCanAddAndRemoveFromMergeQueue: {
    table: {
      disable: true,
    },
  },
}

const meta: Meta<typeof MergeQueueSection> = {
  title: 'Pull Requests/Merge Box/MergeQueueSection',
  component: MergeQueueSection,
  decorators: [
    Story => (
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <div style={{maxWidth: '600px'}}>
            <Story />
          </div>
        </PageDataContextProvider>
      </MemoryRouter>
    ),
  ],
}

type StoryProps = {
  positionInQueue: number
  mergeQueueEntryState: MergeQueueEntryState
  mergeQueueEntryIsLocked: boolean
  removalState: string
}
type Story = StoryObj<Props & StoryProps>

const dequeuePullRequestPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.dequeuePullRequest}`

const defaultProps = {
  id: 'pullRequest123',
  mergeQueue: {
    url: 'https://github.localhost/monalisa/smile/queue',
  },
  viewerCanAddAndRemoveFromMergeQueue: true,
  focusPrimaryMergeButton: noop,
  refetchMergeBoxQuery: noop,
}

export const MergeQueue: Story = {
  args: {
    positionInQueue: 1,
    mergeQueueEntryState: 'MERGEABLE',
    mergeQueueEntryIsLocked: false,
    viewerCanAddAndRemoveFromMergeQueue: true,
  },
  argTypes: {
    positionInQueue: {control: 'number'},
    mergeQueueEntryState: {
      options: ['AWAITING_CHECKS', 'WAITING', 'MERGEABLE', 'QUEUED', 'UNMERGEABLE'],
      control: 'radio',
    },
    mergeQueueEntryIsLocked: {control: 'boolean'},
    ...disableArgs,
  },
  parameters: {
    msw: {
      handlers: [
        http.post(dequeuePullRequestPageDataRoute, async () => {
          await delay(1000)
          return HttpResponse.json({}, {status: 200})
        }),
      ],
    },
  },
  render: ({positionInQueue, mergeQueueEntryState, mergeQueueEntryIsLocked, ...args}: StoryProps) => {
    const props = {
      ...defaultProps,
      ...args,
      mergeQueueEntry: {
        position: positionInQueue,
        state: mergeQueueEntryState,
        isLocked: mergeQueueEntryIsLocked,
      },
    }

    return <MergeQueueSection {...props} />
  },
}

export const DequeueSuccess: Story = {
  argTypes: disableArgs,
  parameters: {
    msw: {
      handlers: [
        http.post(dequeuePullRequestPageDataRoute, async () => {
          await delay(1000)
          return HttpResponse.json({}, {status: 200})
        }),
      ],
    },
  },
  render: () => {
    return <MergeQueueSection {...defaultProps} mergeQueueEntry={{position: 2, state: 'MERGEABLE', isLocked: false}} />
  },
}

export const DequeueFailure: Story = {
  argTypes: disableArgs,
  parameters: {
    msw: {
      handlers: [
        http.post(dequeuePullRequestPageDataRoute, async () => {
          await delay(1000)
          return HttpResponse.json({error: 'Whoops!'}, {status: 422})
        }),
      ],
    },
  },
  render: () => {
    return <MergeQueueSection {...defaultProps} mergeQueueEntry={{position: 2, state: 'MERGEABLE', isLocked: false}} />
  },
}

export default meta
