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
      mockResponse({choices: [{message: {content: '```json{"An issue title": "An issue summary"}\n```'}}]})
    })

    it('sends the prompt', async () => {
      const messages = [
        {role: 'system', content: 'prompt'},
        {role: 'user', content: 'content'},
      ]
      mockedMessageBuilder.mockReturnValue(messages)

      const client = new CopilotAPIClient()
      const prompt = 'Do this not that'
      const temperature = 0.5
      await client.getIssueSummariesByTitle([], prompt, temperature)

      expect(mockedMakeCapiRequest).toHaveBeenCalledWith(
        expect.objectContaining({body: expect.objectContaining({messages})}),
      )
    })

    it('sends the integration id', async () => {
      const client = new CopilotAPIClient()
      const prompt = 'Do this not that'
      const temperature = 0.5
      await client.getIssueSummariesByTitle([], prompt, temperature)
      expect(mockedMakeCapiRequest).toHaveBeenCalledWith(
        expect.objectContaining({
          integrationId: 'copilot-embedded-experience',
        }),
      )
    })

    it('parses the response', async () => {
      const client = new CopilotAPIClient()
      const prompt = 'Do this not that'
      const temperature = 0.5
      const resp = client.getIssueSummariesByTitle([], prompt, temperature)
      await expect(resp).resolves.toEqual(new Map([['An issue title', 'An issue summary']]))
    })
  })
})
