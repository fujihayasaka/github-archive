import {hasMatch} from 'fzy.js'
import type {HttpHandler} from 'msw'
import {delay, http, HttpResponse} from 'msw'

import {
  getDiscussionReferenceMock,
  getDocsetMock,
  getFileReferenceMock,
  getIssueReferenceMock,
  getPullRequestReferenceMock,
  getRepositoryReferenceMock,
} from '../../../test-utils/mock-data'
import mockDiscussions from './mock-discussions'
import mockIssues from './mock-issues'
import mockPullRequests from './mock-pull-requests'
import mockRepos from './mock-repos'

export function getGraphqlQueryHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get(`/_graphql`, async ({request: req}) => {
    const params = new URL(req.url, window.location.origin).searchParams
    const body = JSON.parse(params.get('body') ?? '{}') as {searchQuery?: string}
    const query = body.searchQuery?.split(' ')[0]

    // this is awful
    const repos = mockRepos.map((r, i) => ({
      id: i.toString(),
      databaseId: i,
      name: r.name,
      nameWithOwner: r.nameWithOwner,
      owner: {
        __typename: 'Organization',
        databaseId: 9919,
        login: r.owner,
        avatarUrl: 'https://avatars.githubusercontent.com/u/9919?s=64&v=4',
        issueTypesEnabled: true,
        id: r.owner,
      },
      isPrivate: true,
      visibility: r.visibility,
      isArchived: false,
      isInOrganization: true,
      hasIssuesEnabled: true,
      slashCommandsEnabled: true,
      viewerCanPush: true,
      isBlankIssuesEnabled: true,
      viewerIssueCreationPermissions: {
        labelable: true,
        milestoneable: true,
        assignable: true,
        triageable: true,
        typeable: true,
      },
      securityPolicyUrl: 'https://github.com/github/github/security/policy',
      contributingFileUrl: 'https://github.com/github/.github/blob/main/CONTRIBUTING.md',
      codeOfConductFileUrl: 'https://github.com/github/.github/blob/main/CODE_OF_CONDUCT.md',
      supportFileUrl: null,
      shortDescriptionHTML: '...',
      planFeatures: {
        maximumAssignees: 10,
      },
    }))

    await delay(mockedNetworkTimeout)

    if (!query)
      return HttpResponse.json({
        data: {
          viewer: {
            topRepositories: {
              edges: repos.slice(0, 5).map(repo => ({node: repo})),
            },
          },
        },
      })

    return HttpResponse.json({
      data: {
        search: {
          nodes: repos
            .filter(r => {
              return hasMatch(query, r.name) || hasMatch(query, r.owner.login)
            })
            .slice(0, 5)
            .map(repo => ({node: repo})),
        },
      },
    })
  })
}

export function getIssueSuggestionsHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get(`/copilot/chat/autocomplete/issues`, async ({request: req}) => {
    const params = new URL(req.url, window.location.origin).searchParams
    const q = params.get('q')
    const repo = params.get('repo')
    if (!q) {
      return HttpResponse.json(mockIssues.filter(i => i.repository === repo).slice(0, 10))
    }

    await delay(mockedNetworkTimeout)
    return HttpResponse.json(
      mockIssues.filter(i => {
        return i.repository === repo && (hasMatch(q, i.title) || hasMatch(q, i.number.toString()))
      }),
    )
  })
}

export function getAgentsHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get(`agents`, async () => {
    await delay(mockedNetworkTimeout)
    return HttpResponse.json([])
  })
}

export function getPullRequestSuggestionsHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get(`/copilot/chat/autocomplete/pulls`, async ({request: req}) => {
    const params = new URL(req.url, window.location.origin).searchParams
    const q = params.get('q')
    const repo = params.get('repo')
    if (!q) {
      return HttpResponse.json(mockPullRequests.filter(p => p.repository === repo).slice(0, 10))
    }

    await delay(mockedNetworkTimeout)
    return HttpResponse.json(
      mockPullRequests.filter(p => {
        return p.repository === repo && (hasMatch(q, p.title) || hasMatch(q, p.number.toString()))
      }),
    )
  })
}

export function getDiscussionSuggestionsHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get(`/copilot/chat/autocomplete/discussions`, async ({request: req}) => {
    const params = new URL(req.url, window.location.origin).searchParams
    const q = params.get('q')
    const repo = params.get('repo')
    if (!q) {
      return HttpResponse.json(mockDiscussions.filter(d => d.repository === repo).slice(0, 10))
    }

    await delay(mockedNetworkTimeout)
    return HttpResponse.json(
      mockDiscussions.filter(d => {
        return d.repository === repo && (hasMatch(q, d.title) || hasMatch(q, d.number.toString()))
      }),
    )
  })
}

export function getChatLinksHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get('/copilot/chat-links', async ({request}) => {
    const rootUrl = new URL(request.url, request.referrer)
    // Extract the item_url query parameter
    // ex. /copilot/chat-links?item_url=https://github.com/github/copilot-chat/issues/1234'
    // ex. /copilot/chat-links?item_url=https://github.com/github/copilot-chat/pull/1234'

    const itemUrl = rootUrl.searchParams.get('item_url')
    if (itemUrl) {
      const url = new URL(itemUrl, request.referrer)
      const [owner, repo, type, ...idParts] = url.pathname.split('/').filter(Boolean)
      const id = idParts.join('/')

      await delay(mockedNetworkTimeout)

      switch (type) {
        case 'issues':
          return HttpResponse.json(getIssueReferenceMock(id, repo, owner))
        case 'pull':
          return HttpResponse.json(getPullRequestReferenceMock(id, repo, owner))
        case 'discussions':
          return HttpResponse.json(getDiscussionReferenceMock(id, repo, owner))
        case 'tree': {
          const [refA, refB, ...pathParts] = id.split('/')
          return HttpResponse.json(getFileReferenceMock(`${refA}/${refB}`, pathParts.join('/'), repo, owner))
        }
      }
    }

    return HttpResponse.json({status: 404})
  })
}

export function getChatReferenceRepositoryHandler(mockedNetworkTimeout = 10): HttpHandler {
  return http.get('/copilot/chat/reference/:owner/:repo', async ({params}) => {
    const {owner, repo} = params

    if (owner && repo) {
      await delay(mockedNetworkTimeout)
      // Note: this repo mock may have more details than the real endpoint
      return HttpResponse.json(getRepositoryReferenceMock(owner as string, repo as string))
    }
    return HttpResponse.json({status: 404})
  })
}

export function getChatReferenceHandlerV2(mockedNetworkTimeout = 10): HttpHandler {
  return http.get('/copilot/chat/reference/:owner/:repo/:type/:number', async ({params}) => {
    const {owner, repo, type, number} = params

    if (owner && repo && number) {
      await delay(mockedNetworkTimeout)

      switch (type) {
        case 'issue':
          return HttpResponse.json(getIssueReferenceMock(number as string, repo as string, owner as string))
        case 'pull_request':
          return HttpResponse.json(getPullRequestReferenceMock(number as string, repo as string, owner as string))
        case 'discussion':
          return HttpResponse.json(getDiscussionReferenceMock(number as string, repo as string, owner as string))
        default:
          return HttpResponse.json({status: 404})
      }
    }

    return HttpResponse.json({status: 404})
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
