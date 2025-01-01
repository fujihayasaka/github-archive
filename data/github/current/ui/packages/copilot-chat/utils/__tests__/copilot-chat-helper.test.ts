import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'

import {makeCAPIRequest} from '../copilot-chat-helpers'

const fetchMock = jest.spyOn(global, 'fetch')
fetchMock.mockResolvedValue({
  json: () => {},
  ok: true,
  status: 200,
  headers: new Headers({'Content-Type': 'application/json'}),
} as Response)

describe('makeCAPIRequest', () => {
  const mockToken = new AuthToken('keyboard cat', 'no expiry', [])

  describe('API Version Header', () => {
    it('api version header is not set when API version is undefined', async () => {
      await makeCAPIRequest({
        authToken: mockToken,
        basePath: '/foo/',
        body: {},
        method: 'GET',
        integrationId: 'test-integration-id',
        path: '/bar',
        streamingResponse: false,
      })
      const headers = fetchMock.mock.lastCall?.[1]?.headers
      expect(headers).not.toHaveProperty('X-GitHub-Api-Version')
    })
    it('api version header is set when API version is present', async () => {
      const expectedApiVersion = '2025-05-01'
      await makeCAPIRequest({
        authToken: mockToken,
        basePath: '/foo/',
        body: {},
        method: 'GET',
        integrationId: 'test-integration-id',
        path: '/bar',
        streamingResponse: false,
        apiVersion: expectedApiVersion,
      })
      const headers = fetchMock.mock.lastCall?.[1]?.headers
      expect(headers).toHaveProperty('X-GitHub-Api-Version', expectedApiVersion)
    })
  })
})
