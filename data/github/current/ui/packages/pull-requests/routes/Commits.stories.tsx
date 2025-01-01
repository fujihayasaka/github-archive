import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {getCommitsRoutePayload} from '../test-utils/commits/commits-mock-data'
import {Commits} from './Commits'

const meta: Meta<typeof Commits> = {
  title: 'Pull Requests/Commits',
  component: Commits,
  decorators: [
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={`${BASE_PAGE_DATA_URL}/commits`}>
          <Story />
        </PageDataContextProvider>
      )
    },
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
}

export default meta

const defaultRoutePayload = getCommitsRoutePayload()
const defaultAppPayload = {helpUrl: ''}

type Story = StoryObj<typeof Commits>

export const Default: Story = {
  render: () => (
    <Wrapper routePayload={defaultRoutePayload} appPayload={defaultAppPayload}>
      <Commits />
    </Wrapper>
  ),
}

export const NoCommits: Story = {
  render: () => {
    const routePayload = {...defaultRoutePayload, commitGroups: []}
    return (
      <Wrapper routePayload={routePayload} appPayload={defaultAppPayload}>
        <Commits />
      </Wrapper>
    )
  },
}

export const GitRpcTimeout: Story = {
  render: () => {
    const timeOutMessage = `git log ${defaultRoutePayload.pullRequest.headBranch}`
    const routePayload = {...defaultRoutePayload, timeOutMessage, commitGroups: []}
    return (
      <Wrapper routePayload={routePayload} appPayload={defaultAppPayload}>
        <Commits />
      </Wrapper>
    )
  },
}

export const TooManyCommits: Story = {
  render: () => {
    const routePayload = {...defaultRoutePayload, truncated: true}
    return (
      <Wrapper routePayload={routePayload} appPayload={defaultAppPayload}>
        <Commits />
      </Wrapper>
    )
  },
}
