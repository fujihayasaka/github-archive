import {assert, setup, suite, test} from '@github-ui/browser-tests'
import {getPageViewsMap, logPageView, scorer, type PageViews} from '../page-views'

suite('page-views', () => {
  const VIEWS_KEY = 'jump_to:page_views'

  let originalDateNowFunction: typeof Date.now
  let originalLocalStorage: Storage

  setup(() => {
    originalDateNowFunction = Date.now
    originalLocalStorage = window.localStorage
    Date.now = () => {
      return 42000
    }
  })

  teardown(() => {
    Date.now = originalDateNowFunction

    // Restore window.localStorage after each test.
    Object.defineProperty(window, 'localStorage', {
      get() {
        return originalLocalStorage
      },
    })
    window.localStorage.clear()
  })

  suite('limitedPageViews', () => {
    // Create 101 page view records in order to GC half of them.
    const mockPageViews = [...Array(101).keys()].reduce<PageViews>((acc, currentVal, index) => {
      acc[`repository:github/github${currentVal}`] = {
        lastVisitedAt: index * 1000,
        visitCount: currentVal,
      }
      return acc
    }, {})

    test('sets localStorage to a limited response to half the max size', () => {
      window.localStorage.setItem(VIEWS_KEY, JSON.stringify(mockPageViews))
      logPageView('/github/linguist')
      const actual = getPageViewsMap()
      assert.equal(Object.keys(actual).length, 50)
      assert.equal(actual[Object.keys(actual)[0]!]!['visitCount'], 100)
      assert.equal(actual[Object.keys(actual)[49]!]!['visitCount'], 51)
    })

    test('returns same object if entries count is under 100', () => {
      const newMockPageViews = [...Array(50).keys()].reduce<PageViews>((acc, currentVal, index) => {
        acc[`repository:github/github${currentVal}`] = {
          lastVisitedAt: index * 1000,
          visitCount: currentVal,
        }
        return acc
      }, {})

      window.localStorage.setItem(VIEWS_KEY, JSON.stringify(newMockPageViews))
      logPageView('/github/linguist')
      const actual = getPageViewsMap()
      assert.equal(Object.keys(actual).length, 51)
      assert.equal(actual[Object.keys(actual)[0]!]!['visitCount'], 0)
      assert.equal(actual[Object.keys(actual)[50]!]!['visitCount'], 1)
    })

    test('returns the records sorted by rankPageViews algorithm', () => {
      const newMockPageViews = deepCopyObj(mockPageViews)
      // visitCount holds the highest weight in the algorithm
      newMockPageViews['repository:github/github1']['visitCount'] = 1000000

      window.localStorage.setItem(VIEWS_KEY, JSON.stringify(newMockPageViews))
      logPageView('/github/linguist')
      const actual = getPageViewsMap()
      assert.equal(Object.keys(actual)[0], 'repository:github/github1')
    })
  })

  suite('getPageViewsMap', () => {
    test('returns empty map when storage is empty', () => {
      assert.deepEqual(getPageViewsMap(), {})
    })

    test('returns empty map when no window.localStorage object', () => {
      Object.defineProperty(window, 'localStorage', {
        get() {
          return null
        },
      })
      assert.deepEqual(getPageViewsMap(), {})
    })

    test('returns empty object when no key does not exist in local storage', () => {
      assert.deepEqual(getPageViewsMap(), {})
    })

    test('returns empty map when accessing localStorage throws an error', () => {
      // https://github.com/github/github/issues/90956
      // firefox on some platforms throws if you access window.localStorage when it's disabled
      Object.defineProperty(window, 'localStorage', {
        get() {
          throw new Error('This operation is insecure')
        },
      })
      assert.deepEqual(getPageViewsMap(), {})
    })

    test('returns an empty Map when storage is disabled', () => {
      Object.defineProperty(window, 'localStorage', {
        get() {
          return new FakeDisabledLocalStorage()
        },
      })
      assert.deepEqual(getPageViewsMap(), {})
    })

    test('returns an empty map when storage contains garbage', () => {
      // valid json concatenated with a legacy string
      const garbage = '{"some":"json"} project:some/project'
      window.localStorage.setItem(VIEWS_KEY, garbage)
      assert.deepEqual(getPageViewsMap(), {})
    })

    test('it skips keys which are not valid page view keys', () => {
      const json = JSON.stringify({
        '{"weird json key": 123}': {lastVisitedAt: 36, visitCount: 1},
        'repository:octokit/octokit.rb': {lastVisitedAt: 39, visitCount: 1},
      })
      window.localStorage.setItem(VIEWS_KEY, json)
      const expected = {
        'repository:octokit/octokit.rb': {lastVisitedAt: 39, visitCount: 1},
      }
      assert.deepEqual(getPageViewsMap(), expected)
    })

    test('returns correct page views when storage contains new format', () => {
      const expected = {
        'project:campus/profile.io/1': {lastVisitedAt: 42, visitCount: 1},
        'team:github/panda': {lastVisitedAt: 42, visitCount: 2},
        'repository:github/github.io': {lastVisitedAt: 42, visitCount: 3},
        'project:github/103': {lastVisitedAt: 42, visitCount: 1},
      }
      window.localStorage.setItem(VIEWS_KEY, JSON.stringify(expected))
      assert.deepEqual(getPageViewsMap(), expected)
    })
  })

  suite('logPageView', () => {
    test('logs a team page view for a team that has never been visited before', () => {
      logPageView('/orgs/github/teams/ee-panda-rocket')
      const pageViewMap = getPageViewsMap()
      const actual = pageViewMap['team:github/ee-panda-rocket']
      const expected = {lastVisitedAt: 42, visitCount: 1}
      assert.deepEqual(actual, expected)
    })

    test('logs a repository page view for a repository that has never been visited before', () => {
      logPageView('/github/github.io')
      const expected = {lastVisitedAt: 42, visitCount: 1}
      const actual = getPageViewsMap()['repository:github/github.io']
      assert.deepEqual(actual, expected)
    })

    test('logs a project page view for a repository-owned project that has never been visited before', () => {
      logPageView('/github/github.io/projects/1')
      const expected = {lastVisitedAt: 42, visitCount: 1}
      const actual = getPageViewsMap()['project:github/github.io/1']
      assert.deepEqual(actual, expected)
    })

    test('logs a project page view for an organization-owned project that has never been visited before', () => {
      logPageView('/orgs/github/projects/402')
      const expected = {lastVisitedAt: 42, visitCount: 1}
      const actual = getPageViewsMap()['project:github/402']
      assert.deepEqual(actual, expected)
    })

    test('logs a team page view for a team that has been visited before', () => {
      window.localStorage.setItem(
        VIEWS_KEY,
        JSON.stringify({
          'team:github/ee-panda-rocket': {
            lastVisitedAt: 21,
            visitCount: 10,
          },
        }),
      )
      logPageView('/orgs/github/teams/ee-panda-rocket')
      const expected = {lastVisitedAt: 42, visitCount: 11}
      const actual = getPageViewsMap()['team:github/ee-panda-rocket']
      assert.deepEqual(actual, expected)
    })

    test('logs a repository page view for a repository that has been visited before', () => {
      window.localStorage.setItem(
        VIEWS_KEY,
        JSON.stringify({
          'repository:github/github.io': {
            lastVisitedAt: 2,
            visitCount: 88,
          },
        }),
      )
      logPageView('/github/github.io')
      const expected = {lastVisitedAt: 42, visitCount: 89}
      const actual = getPageViewsMap()['repository:github/github.io']
      assert.deepEqual(actual, expected)
    })

    test('logs a project page view for a repository-owned project that has been visited before', () => {
      window.localStorage.setItem(
        VIEWS_KEY,
        JSON.stringify({
          'project:github/github.io/1': {
            lastVisitedAt: 7,
            visitCount: 2,
          },
        }),
      )
      logPageView('/github/github.io/projects/1')
      const expected = {lastVisitedAt: 42, visitCount: 3}
      const actual = getPageViewsMap()['project:github/github.io/1']
      assert.deepEqual(actual, expected)
    })

    test('logs a project page view for an organization-owned project that has been visited before', () => {
      window.localStorage.setItem(
        VIEWS_KEY,
        JSON.stringify({
          'project:github/402': {
            lastVisitedAt: 7,
            visitCount: 2,
          },
        }),
      )
      logPageView('/orgs/github/projects/402')
      const expected = {lastVisitedAt: 42, visitCount: 3}
      const actual = getPageViewsMap()['project:github/402']
      assert.deepEqual(actual, expected)
    })

    test('recognizes repository-owned project page views', () => {
      logPageView('/github/github.io/projects/1')
      assert(getPageViewsMap()['project:github/github.io/1'])
    })

    test('recognizes organization-owned project page views', () => {
      logPageView('/orgs/github/projects/103')
      assert(getPageViewsMap()['project:github/103'])
    })

    test('recognizes top-level repository page views', () => {
      logPageView('/github/github.io')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('recognizes repository blob page views', () => {
      logPageView('/github/github.io/blob/0aa27281b210cca083430a21e83ba935e43139e4/.gitignore')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('recognizes repository tree page views', () => {
      logPageView('/github/github.io/tree/0aa27281b210cca083430a21e83ba935e43139e4')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('recognizes repository pulse page views', () => {
      logPageView('/github/github.io/pulse')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('recognizes issues page views on a repository', () => {
      logPageView('/github/github.io/issues')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('recognizes single issue page view on a repository', () => {
      logPageView('/github/github.io/issues/90218')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('recognizes pulls page views on a repository', () => {
      logPageView('/github/github.io/pulls')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('recognizes single pull request page view on a repository', () => {
      logPageView('/github/github.io/pull/90220')
      assert(getPageViewsMap()['repository:github/github.io'])
    })

    test('does not fail when storage is disabled', () => {
      Object.defineProperty(window, 'localStorage', {
        get() {
          return new FakeDisabledLocalStorage()
        },
      })
      logPageView('/github/github.io/pull/90220')
    })
  })
})

suite('scorer', () => {
  const pageViews = {
    'repository:github/github': {lastVisitedAt: 10, visitCount: 6},
    'repository:github/munger': {lastVisitedAt: 2, visitCount: 5},
    'team:github/employees': {lastVisitedAt: 3, visitCount: 1},
    'team:github/ee-panda-rocket': {lastVisitedAt: 5, visitCount: 8},
  }

  test('blends frequency and recency using the FEATURE_WEIGHTS const', () => {
    // Formula is (relative frequency * frequency weight) + (relative recency * recency weight), so
    // expected corresponding scores would be [0.58, 0.54, 0.25, 0.23]
    const expected = [
      'repository:github/github',
      'team:github/ee-panda-rocket',
      'repository:github/munger',
      'team:github/employees',
    ]
    const scorePage = scorer(pageViews)
    const scored = Object.keys(pageViews).sort((a, b) => scorePage(b) - scorePage(a))
    assert.deepEqual(scored, expected)
  })

  test('defaults frequency of unvisited destination to zero', () => {
    const scorePage = scorer(pageViews)
    assert.equal(scorePage('bogus'), 0)
  })
})

const deepCopyObj = (obj: object) => JSON.parse(JSON.stringify(obj))

export class FakeDisabledLocalStorage {
  key = throwLocalStorageUnavailableError
  getItem = throwLocalStorageUnavailableError
  setItem = throwLocalStorageUnavailableError
  removeItem = throwLocalStorageUnavailableError
  clear = throwLocalStorageUnavailableError
}

function throwLocalStorageUnavailableError() {
  throw new Error('localStorage is not available')
}
