import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {buildMessages} from '../issue-summary-message-builder'
import {CopilotAPIClient} from '../copilot-api-client'

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-helpers')
jest.mock('@github-ui/copilot-auth-token')
jest.mock('../issue-summary-message-builder')

const mockedMakeCapiRequest = makeCAPIRequest as jest.Mock
const mockedMessageBuilder = buildMessages as jest.Mock

function mockResponse(resp: unknown) {
  mockedMakeCapiRequest.mockResolvedValue({
    ok: true,
    json: () => resp,
  })
}

describe('CopilotAPIClient', () => {
  describe('#getIssueSummariesByTitle', () => {
    beforeEach(() => {
      jest.clearAllMocks()
      mockResponse({choices: [{message: {content: '```json{"An issue title": "An issue summary"}\n```'}}]})
    })

    it('sends the prompt', async () => {
      const messages = [
        {role: 'system', content: 'prompt'},
        {role: 'user', content: 'content'},
      ]
      mockedMessageBuilder.mockReturnValue(messages)

      const mockIssue = {
        id: '1',
        title: 'Test Issue',
        description: 'This is a test issue',
        permalink: 'https://github.com/github/github/issues/1',
        commentCount: 0,
        comments: [],
        updatedAt: '2022-02-02T00:00:00Z',
      }

      const client = new CopilotAPIClient()
      const prompt = 'Do this not that'
      const temperature = 0.5
      await client.getIssueSummariesByTitle([mockIssue], prompt, temperature)

      expect(mockedMakeCapiRequest).toHaveBeenCalledWith(
        expect.objectContaining({body: expect.objectContaining({messages})}),
      )
    })

    it('sends the integration id', async () => {
      const mockIssue = {
        id: '1',
        title: 'Test Issue',
        description: 'This is a test issue',
        permalink: 'https://github.com/github/github/issues/1',
        commentCount: 0,
        comments: [],
        updatedAt: '2022-02-02T00:00:00Z',
      }

      const client = new CopilotAPIClient()
      const prompt = 'Do this not that'
      const temperature = 0.5
      await client.getIssueSummariesByTitle([mockIssue], prompt, temperature)
      expect(mockedMakeCapiRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          integrationId: 'copilot-embedded-experience',
        }),
      )
    })

    it('parses the response', async () => {
      const mockIssue = {
        id: '1',
        title: 'Test Issue',
        description: 'This is a test issue',
        permalink: 'https://github.com/github/github/issues/1',
        commentCount: 0,
        comments: [],
        updatedAt: '2022-02-02T00:00:00Z',
      }

      const client = new CopilotAPIClient()
      const prompt = 'Do this not that'
      const temperature = 0.5
      const resp = client.getIssueSummariesByTitle([mockIssue], prompt, temperature)
      await expect(resp).resolves.toEqual(new Map([['An issue title', 'An issue summary']]))
    })

    it('does not make an API call when there are no issues', async () => {
      const client = new CopilotAPIClient()
      const prompt = 'Do this not that'
      const temperature = 0.5

      await client.getIssueSummariesByTitle([], prompt, temperature)

      expect(mockedMessageBuilder).not.toHaveBeenCalled()
      expect(mockedMakeCapiRequest).not.toHaveBeenCalled()
    })
  })
})
