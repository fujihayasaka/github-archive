import {CopilotChatService} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import {
  TREE_COMPARISON_REFERENCE_TYPE,
  type CopilotChatMessage,
  type CopilotChatThread,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {useLoadTreeComparisonQuery$data} from '../__generated__/useLoadTreeComparisonQuery.graphql'
import type {CopilotPrReviewBannerProps} from '../CopilotPrReviewBanner'
import {signChannel} from '@github-ui/use-alive/test-utils'
import {reviewUserMessage} from '@github-ui/copilot-chat/utils/constants'

import {http, HttpResponse, delay} from 'msw'
import {setupServer} from 'msw/node'

export const mockProps: CopilotPrReviewBannerProps = {
  apiURL: 'http://github.localhost:2026',
  ssoOrganizations: [],
  location: 'conversation',
  baseRepoId: 1,
  headRepoId: 1,
  baseRevision: '12345',
  headRevision: '678910',
  analyticsPath: '/github-copilot/someRepoOwner/someRepo/pulls/review-banner?base_sha=12345&head_sha=678910',
  signedWebsocketChannel: signChannel('pull_request:123'),
}

const mockUserLogin = 'SomeNiceUser'

export const mockTreeComparisonResponse: useLoadTreeComparisonQuery$data = {
  node: {
    additions: 50,
    author: {
      login: mockUserLogin,
    },
    baseRefOid: mockProps.baseRevision,
    baseRepository: {databaseId: mockProps.baseRepoId},
    closed: false,
    deletions: 20,
    headRefOid: mockProps.headRevision,
    headRepository: {databaseId: mockProps.headRepoId},
    isDraft: true,
  },
  viewer: {
    login: mockUserLogin,
    isCopilotDotcomChatEnabled: true,
  },
}

export const mockThreadId = '1232342345345'

export const mockThread: CopilotChatThread = {
  id: mockThreadId,
  name: 'test',
  currentReferences: [],
  createdAt: '',
  updatedAt: '',
}

export const mockMessage: CopilotChatMessage = {
  role: 'assistant',
  id: '1232342345345',
  content: 'test completion',
  createdAt: '',
  references: [],
  threadID: mockThreadId,
}

export const mockMessages: CopilotChatMessage[] = [
  {
    role: 'user',
    content: reviewUserMessage,
    id: '',
    createdAt: '',
    threadID: mockThreadId,
    references: [
      {
        type: TREE_COMPARISON_REFERENCE_TYPE,
        baseRepoId: 1,
        headRepoId: 1,
        baseRevision: '',
        headRevision: '',
        diffHunks: [
          {
            type: 'diff-hunk',
            changeReference: '',
            diff: '',
            fileName: '',
            headerContext: '',
          },
        ],
      },
    ],
  },
  mockMessage,
]

export const mockMessagesWithoutDiffHunks: CopilotChatMessage[] = [
  {
    role: 'user',
    content: 'review',
    id: '',
    createdAt: '',
    threadID: mockThreadId,
    references: [
      {
        type: TREE_COMPARISON_REFERENCE_TYPE,
        baseRepoId: 1,
        headRepoId: 1,
        baseRevision: 'ecb31d29db78',
        headRevision: '3b882cddfb99',
        diffHunks: [],
      },
    ],
  },
  mockMessage,
]

export const server = setupServer(
  http.get(`${mockProps.apiURL}/github/chat/threads`, async () => {
    await delay()
    return HttpResponse.json({threads: []})
  }),

  http.get(`${mockProps.apiURL}/github/chat/threads/:threadID/messages`, async () => {
    await delay()
    return HttpResponse.json({thread: mockThread, messages: mockMessages})
  }),

  http.post(`${mockProps.apiURL}/github/chat/threads`, async () => {
    await delay()
    return HttpResponse.json({thread: mockThread})
  }),

  http.post(`${mockProps.apiURL}/github/chat/threads/:threadID/messages`, async () => {
    await delay()
    return HttpResponse.json({message: mockMessage})
  }),

  http.patch(`${mockProps.apiURL}/github/chat/threads/:threadID/name`, async () => {
    await delay()
    return HttpResponse.json({name: 'new thread name'})
  }),
)

export function getMockChatService() {
  const mockChatService = new CopilotChatService(
    mockProps.apiURL ?? 'http://github.localhost/capi',
    mockProps.ssoOrganizations ?? [],
  )
  jest.spyOn(console, 'error').mockImplementation()
  jest.spyOn(mockChatService.copilotAuthTokenProvider, 'getAuthToken').mockImplementation(
    // @ts-expect-error we aren't mocking the whole value
    async () => {
      return {authorizationHeaderValue: 'some value'}
    },
  )
  const mockFetchThreads = jest.spyOn(mockChatService, 'fetchThreads')
  const mockListMessages = jest.spyOn(mockChatService, 'listMessages')
  const mockCreateThread = jest.spyOn(mockChatService, 'createThread')
  const mockCreateMessage = jest.spyOn(mockChatService, 'createMessage')
  const mockRenameThread = jest.spyOn(mockChatService, 'renameThread')
  return {mockChatService, mockCreateThread, mockCreateMessage, mockFetchThreads, mockListMessages, mockRenameThread}
}
