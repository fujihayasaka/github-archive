import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {HttpResponse, http} from 'msw'

import {PullRequestHeader, type PullRequestHeaderProps} from './PullRequestHeader'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {getHeaderPageData, getDiffstatPageData} from '../test-utils/header-mock-data'

const diffstatRoute = `${BASE_PAGE_DATA_URL}/commits/page_data/${PageData.diffstat}`

const meta = {
  title: 'Pull Requests/commits/Header',
  component: PullRequestHeader,
  decorators: [
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={`${BASE_PAGE_DATA_URL}/commits`}>
          <Wrapper appPayload={{helpUrl: ''}}>
            <Story />
          </Wrapper>
        </PageDataContextProvider>
      )
    },
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof PullRequestHeader>

export default meta

const defaultArgs = getHeaderPageData()

type Story = StoryObj<typeof PullRequestHeader>

const defaultHandlers = [
  http.get(diffstatRoute, () => {
    return HttpResponse.json(getDiffstatPageData())
  }),
]

export const Open: Story = {
  args: defaultArgs,
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const Closed: Story = {
  args: {
    ...defaultArgs,
    pullRequest: {
      ...defaultArgs['pullRequest'],
      state: 'CLOSED',
    },
    user: {
      ...defaultArgs['user'],
      canChangeBase: false,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const Queued: Story = {
  args: {
    ...defaultArgs,
    pullRequest: {
      ...defaultArgs['pullRequest'],
      state: 'QUEUED',
    },
    user: {
      ...defaultArgs['user'],
      canChangeBase: false,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const Merged: Story = {
  args: {
    ...defaultArgs,
    pullRequest: {
      ...defaultArgs['pullRequest'],
      state: 'MERGED',
    },
    user: {
      ...defaultArgs['user'],
      canChangeBase: false,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const Draft: Story = {
  args: {
    ...defaultArgs,
    pullRequest: {
      ...defaultArgs['pullRequest'],
      state: 'DRAFT',
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const CannotEditTitle: Story = {
  args: {
    ...defaultArgs,
    user: {
      ...defaultArgs['user'],
      canEditTitle: false,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const CannotChangeBase: Story = {
  args: {
    ...defaultArgs,
    user: {
      ...defaultArgs['user'],
      canChangeBase: false,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const CodespacesDisabled: Story = {
  args: {
    ...defaultArgs,
    repository: {
      ...defaultArgs['repository'],
      codespacesEnabled: false,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const CodespacesEnterprise: Story = {
  args: {
    ...defaultArgs,
    repository: {
      ...defaultArgs['repository'],
      isEnterprise: true,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}

export const CopilotEnabled: Story = {
  args: {
    ...defaultArgs,
    repository: {
      ...defaultArgs['repository'],
      copilotEnabled: true,
    },
  },
  parameters: {
    msw: {
      handlers: defaultHandlers,
    },
  },
  render: (args: PullRequestHeaderProps) => <PullRequestHeader {...args} />,
}
