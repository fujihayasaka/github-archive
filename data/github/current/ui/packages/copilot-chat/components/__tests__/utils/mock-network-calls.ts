import type {HttpHandler} from 'msw'
import {delay, http, HttpResponse} from 'msw'

import {getDocsetMock} from '../../../test-utils/mock-data'
import type {IssueReference} from '../../../utils/copilot-chat-types'

export function getIssueDetailsHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get('/copilot/chat-links', async ({request}) => {
    const rootUrl = new URL(request.url, request.referrer)
    // Extract the item_url query parameter (ex. /copilot/chat-links?item_url=https://github.com/github/copilot-chat/issues/1234')
    const itemUrl = rootUrl.searchParams.get('item_url')
    if (itemUrl && itemUrl.includes('issues')) {
      const url = new URL(itemUrl, request.referrer)

      const splitPath = url.pathname.split('/').filter(text => text !== '')

      const owner = splitPath[0]
      const repo = splitPath[1]
      const issueNum = splitPath[3]

      await delay(mockedNetworkTimeout)

      return HttpResponse.json({
        type: 'issue',
        id: issueNum,
        number: Number(issueNum),
        repository: {
          id: Number(issueNum),
          name: repo,
          owner,
        },
        title: 'This is a test issue',
        url: 'https://github.com/github/copilot-chat/issues/1234',
      } as unknown as IssueReference)
    } else {
      return HttpResponse.json({status: 404})
    }
  })
}

export function getKnowledgeBaseHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get('/github-copilot/docs/docsets', async () => {
    await delay(mockedNetworkTimeout)

    const knowledgeBases = [getDocsetMock()]
    return HttpResponse.json({knowledgeBases, administratedCopilotEnterpriseOrganizations: []})
  })
}

export const kbIndexedRepoMock = () =>
  http.get('/github-copilot/docs/docsets/kb_indexed_repos', () => {
    return HttpResponse.json({canChat: true})
  })

export const copilotTokenMock = () => http.post('/github-copilot/chat/token', () => HttpResponse.json({status: 200}))
