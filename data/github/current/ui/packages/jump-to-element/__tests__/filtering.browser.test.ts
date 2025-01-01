import {describe, it} from '@github-ui/tests'
import {assert} from '@github-ui/tests/browser'
import {filterSuggestions} from '../filtering'
import type {Suggestion} from '../model'

describe('filterSuggestions', function () {
  const suggestions: Suggestion[] = [
    {
      type: 'Repository',
      databaseId: 1,
      name: 'github/linguist',
      path: '/github/linguist',
      avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
      owner: {name: 'github', __typename: 'Organization'},
      number: 1,
      rank: 1,
      pageKey: 'github/linguist',
    },
    {
      type: 'Repository',
      databaseId: 2,
      name: 'lerebear/my-repository',
      path: '/lerebear/my-repository',
      avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
      owner: {name: 'github', __typename: 'Organization'},
      number: 1,
      rank: 1,
      pageKey: 'github/linguist',
    },
    {
      type: 'Team',
      databaseId: 3,
      name: '@github/employees',
      path: '/orgs/github/teams/employees',
      avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
      owner: {name: 'github', __typename: 'Organization'},
      number: 1,
      rank: 1,
      pageKey: 'github/linguist',
    },
    {
      type: 'Project',
      databaseId: 1,
      name: '@project engagement',
      path: '/github/linguist/projects/1',
      avatarUrl: 'http://alambic.github.localhost/avatars/u/1?s=56',
      owner: {name: 'github', __typename: 'Organization'},
      number: 1,
      rank: 1,
      pageKey: 'github/linguist',
    },
  ] as const

  it('returns suggestions if field is empty', function () {
    const response = filterSuggestions(suggestions, '', '')
    assert.deepEqual(response, suggestions)
  })

  it('filters the ignore path records out of the suggestions', function () {
    const response = filterSuggestions(suggestions, '', '/github/linguist')
    assert.deepEqual(response, [suggestions[1], suggestions[2], suggestions[3]])
  })

  it('filters the ignore path records out of the suggestions even when searching for it', function () {
    const response = filterSuggestions(suggestions, 'ling', '/github/linguist')
    assert.isEmpty(response)
  })

  it('removes whitespace from string as name cannot contain whitespace', function () {
    const response = filterSuggestions(suggestions, 'li ng', '')
    assert.deepEqual(response, [suggestions[0]])
  })

  it('fuzzily searches for suggestions based on the query text', function () {
    const response = filterSuggestions(suggestions, 'ling', '')
    assert.deepEqual(response, [suggestions[0]])
  })

  it('searches teams if the query starts with @', function () {
    const response = filterSuggestions(suggestions, '@github/employees', '')
    assert.deepEqual(response, [suggestions[2]])
  })

  it('searches projects where the @ symbol is in the name', function () {
    const response = filterSuggestions(suggestions, '@project', '')
    assert.deepEqual(response, [suggestions[3]])
  })
})
