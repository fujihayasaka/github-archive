import {pullRequestUrl} from '../urls'

describe('pullRequestUrl', () => {
  test('returns the route for a pull request when given correct arguments', () => {
    const url = pullRequestUrl({owner: 'monalisa', repoName: 'smile', number: '1'})
    expect(url).toEqual('/monalisa/smile/pull/1')
  })
  test('throws an error if given an undefined argument', () => {
    expect(() => pullRequestUrl({owner: undefined, repoName: 'smile', number: '1'})).toThrow(
      'Cannot generate pull request url',
    )
  })
})
