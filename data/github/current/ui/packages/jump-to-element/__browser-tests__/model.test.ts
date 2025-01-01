import {assert, setup, suite, test} from '@github-ui/browser-tests'
import {parseSuggestionsResponse, updateSearchURL, type SuggestionsResponse} from '../model'

suite('updateSearchUrlParams', () => {
  const baseUrl = 'https://github.com/'
  const url = `${baseUrl}?q=1`

  test('updates url to have new q parameter value', () => {
    const expected = `${baseUrl}?q=changed`
    assert.equal(updateSearchURL('changed', url), expected)
  })

  test('does not add the q parameter if it does not exist', () => {
    assert.equal(updateSearchURL('changed', baseUrl), baseUrl)
  })
})

suite('parseSuggestionsResponse', () => {
  let response: SuggestionsResponse

  setup(function () {
    response = {
      data: {
        suggestions: {
          nodes: [
            {
              type: 'Project',
              databaseId: 1,
              path: '/github/github/projects/302',
              avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
              name: 'Repo Project',
              number: 302,
              owner: {
                __typename: 'Repository',
                name: 'github/github',
              },
              rank: 1,
              pageKey: 'project:github/github/302',
            },
            {
              type: 'Project',
              databaseId: 2,
              name: 'Org Project',
              path: '/github/projects/402',
              avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
              number: 402,
              owner: {
                __typename: 'Organization',
                name: 'github',
              },
              rank: 2,
              pageKey: 'project:github/402',
            },
            {
              databaseId: 3,
              name: 'github/github',
              path: '/github/github',
              avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
              number: 1,
              type: 'Repository',
              owner: {
                __typename: 'Organization',
                name: 'github',
              },
              rank: 3,
              pageKey: 'repository:github/github',
            },
            {
              databaseId: 4,
              name: 'github/ee-panda-rocket',
              path: '/orgs/github/teams/ee-panda-rocket',
              avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
              number: 1,
              type: 'Team',
              owner: {
                __typename: 'Organization',
                name: 'github',
              },
              rank: 4,
              pageKey: 'team:github/ee-panda-rocket',
            },
          ],
        },
      },
    } as const
  })

  test('returns a project key when suggestion type is Repository Project', () => {
    const suggestions = parseSuggestionsResponse(response)
    assert.equal(suggestions[0]!.pageKey, 'project:github/github/302')
  })

  test('returns a project key when suggestion type is Org Project', () => {
    const suggestions = parseSuggestionsResponse(response)
    assert.equal(suggestions[1]!.pageKey, 'project:github/402')
  })

  test('returns a repository key when suggestion type is Repository', () => {
    const suggestions = parseSuggestionsResponse(response)
    assert.equal(suggestions[2]!.pageKey, 'repository:github/github')
  })

  test('returns a team key when suggestion type is Team', () => {
    const suggestions = parseSuggestionsResponse(response)
    assert.equal(suggestions[3]!.pageKey, 'team:github/ee-panda-rocket')
  })
})
