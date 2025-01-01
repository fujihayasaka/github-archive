import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {makeCAPIRequest} from '../copilot-chat-helpers'
import {CopilotChatService} from '../copilot-chat-service'
import {getCopilotExperiments} from '../experiments'

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch')
jest.mock('@github-ui/copilot-chat/utils/copilot-local-storage')
jest.mock('../experiments')
jest.mock('../copilot-chat-helpers')
const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
const mockExperiments = getCopilotExperiments as jest.Mock
const makeCAPIRequestJSON = makeCAPIRequest as jest.Mock

class TestCopilotChatService extends CopilotChatService {
  constructor() {
    super('http://localhost', [])

    this.copilotAuthTokenProvider = new CopilotAuthTokenProvider([])
  }

  testGetAuthToken() {
    return this.copilotAuthTokenProvider.getAuthToken()
  }

  testDotcomRequest() {
    return this.makeDotcomRequest('/test', 'GET')
  }

  testCAPIRequest(path: string) {
    return this.makeCAPIRequest(path, 'GET')
  }
}

function mockCachedToken() {
  jest
    .spyOn(CopilotAuthTokenProvider.prototype, 'getLocalStorageAuthToken')
    .mockReturnValue(new AuthToken('buttercakes', 'no expiry', []))
}

function mockResponse(resp: unknown) {
  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    json: () => resp,
  })
}

describe('CopilotChatService', () => {
  afterEach(jest.resetAllMocks)

  describe('#getAuthToken', () => {
    it('returns a cached token', async () => {
      mockCachedToken()

      const service = new TestCopilotChatService()

      const token = await service.testGetAuthToken()

      expect(token.value).toEqual('buttercakes')
    })

    it('fetches a new token', async () => {
      mockResponse({
        token: 'something else',
        expiration: 'whenever',
      })

      const service = new TestCopilotChatService()

      const token = await service.testGetAuthToken()

      expect(token.value).toEqual('something else')
      expect(token.expiration).toEqual('whenever')
    })
  })

  describe('#makeDotcomRequest', () => {
    beforeEach(() => {
      mockResponse({docsets: []})
      mockExperiments.mockReturnValue(['no_value', 'with_value=123'])
    })

    it('does not send the X-Copilot-Api-Token header by default', async () => {
      const service = new TestCopilotChatService()

      await service.testDotcomRequest()

      expect(mockVerifiedFetchJSON.mock.lastCall[1].headers['X-Copilot-Api-Token']).toBeUndefined()
    })

    it('sends the X-Copilot-Api-Token header when the feature is enabled', async () => {
      mockCachedToken()

      const service = new TestCopilotChatService()

      const docsets = await service.listDocsets()

      expect(docsets).toBeDefined()
      expect(mockVerifiedFetchJSON.mock.lastCall[1].headers['X-Copilot-Api-Token']).toEqual('buttercakes')
    })

    it('sends experiment headers with dashified keys', async () => {
      mockExperiments.mockReturnValue(['no_value', 'with_some_value=123'])

      const service = new TestCopilotChatService()
      await service.testDotcomRequest()

      expect(mockVerifiedFetchJSON.mock.lastCall[1].headers['X-Experiment-no-value']).toEqual('1')
      expect(mockVerifiedFetchJSON.mock.lastCall[1].headers['X-Experiment-with-some-value']).toEqual('123')
    })

    it('does not send API version when the apiVersion prop is undefined', async () => {
      mockExperiments.mockReturnValue(['no_value', 'with_some_value=123'])
      const service = new TestCopilotChatService()
      await service.testCAPIRequest('/test')
      expect(makeCAPIRequestJSON.mock.lastCall[0].apiVersion).toBeUndefined()
    })

    it('sends API version when the apiVersion prop is defined', async () => {
      mockExperiments.mockReturnValue(['no_value', 'with_some_value=123'])
      const service = new TestCopilotChatService()
      const expected = '2025-04-01'
      service.apiVersion = expected
      await service.testCAPIRequest('/test')
      expect(makeCAPIRequestJSON.mock.lastCall[0].apiVersion).toEqual(expected)
    })
  })

  describe('listMessages', () => {
    let service: CopilotChatService
    let mockMakeCAPIRequest: jest.SpyInstance

    beforeEach(() => {
      service = new TestCopilotChatService()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      mockMakeCAPIRequest = jest.spyOn(service as any, 'makeCAPIRequest')
    })

    afterEach(() => {
      jest.restoreAllMocks()
      jest.resetAllMocks()
    })

    it('filters custom copilot references', async () => {
      const customCopilotRef = {
        type: 'file',
        url: '',
        path: './path/to/file.txt',
        repoID: 123,
        repoOwner: 'monalisa',
        repoName: 'smile',
        ref: 'main',
        commitOID: 'abc123',
        refOrigin: 'custom_copilot',
      }
      const githubFileRef = {
        type: 'file',
        url: '',
        path: './path/to/file.txt',
        repoID: 123,
        repoOwner: 'monalisa',
        repoName: 'smile',
        ref: 'main',
        commitOID: 'abc123',
      }
      mockMakeCAPIRequest.mockResolvedValue({
        ok: true,
        json: () => ({
          thread: {id: 'thread1'},
          messages: [{id: 'message1', references: [customCopilotRef, githubFileRef]}],
        }),
      })

      const result = await service.listMessages('thread1')

      expect(result.ok).toBe(true)
      expect(result.payload).toEqual({
        thread: {id: 'thread1'},
        messages: [
          {
            id: 'message1',
            references: [githubFileRef],
          },
        ],
      })
    })

    it('handles cases where messages are not an array', async () => {
      mockMakeCAPIRequest.mockResolvedValue({
        ok: true,
        json: () => ({
          thread: {id: 'thread1'},
          messages: null,
        }),
      })

      const result = await service.listMessages('thread1')

      expect(result.ok).toBe(true)
      expect(result.payload).toEqual({
        thread: {id: 'thread1'},
        messages: null,
      })
    })
  })
})
