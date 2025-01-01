import {QUERIES} from '@github-ui/query-builder/constants/queries'
import {VIEW_IDS} from '../constants/view-constants'
import {searchUrl, issuesAtLabelShowUrl} from '../issue-url-helper'

const ssrSafeLocationMock = jest.fn()

jest.mock('@github-ui/ssr-utils', () => ({
  get ssrSafeLocation() {
    return ssrSafeLocationMock()
  },
}))

describe('searchUrl', () => {
  test('searchUrl returns default value', () => {
    const url = searchUrl({viewId: undefined, query: undefined})
    expect(url).toBe('/issues')
  })

  test('searchUrl returns clean url when query matched assignedToMe saved view', () => {
    const url = searchUrl({viewId: undefined, query: QUERIES.assignedToMe})
    expect(url).toBe('/issues/assigned')
  })

  test('searchUrl returns clean url when query matched created saved view', () => {
    const url = searchUrl({viewId: undefined, query: QUERIES.createdByMe})
    expect(url).toBe('/issues/created')
  })

  test('searchUrl returns clean url when query matched mentioned saved view', () => {
    const url = searchUrl({viewId: undefined, query: QUERIES.mentioned})
    expect(url).toBe('/issues/mentioned')
  })

  test('searchUrl returns url from assigned viewId', () => {
    const url = searchUrl({viewId: VIEW_IDS.assignedToMe, query: undefined})
    expect(url).toBe('/issues/assigned')
  })

  test('searchUrl returns url from created viewId', () => {
    const url = searchUrl({viewId: VIEW_IDS.created, query: undefined})
    expect(url).toBe('/issues/created')
  })

  test('searchUrl returns url from mentioned viewId', () => {
    const url = searchUrl({viewId: VIEW_IDS.mentioned, query: undefined})
    expect(url).toBe('/issues/mentioned')
  })

  test('searchUrl returns url from recent viewId', () => {
    const url = searchUrl({viewId: VIEW_IDS.recent, query: undefined})
    expect(url).toBe('/issues/recent')
  })

  test('searchUrl returns view uid', () => {
    const url = searchUrl({viewId: 'some_global_id'})
    expect(url).toBe(`/issues/some_global_id`)
  })

  test('searchUrl does not return clean url when there is a custom view uid', () => {
    const url = searchUrl({viewId: 'some_global_id', query: QUERIES.assignedToMe})
    expect(url).toBe(`/issues/some_global_id?q=${encodeURIComponent(QUERIES.assignedToMe)}`)
  })

  test('searchUrl returns url when running at the repository level', () => {
    const repoNames = ['repo', 'repo.-_', '.repo', '_repo', '-repo_repo_-repo.repo-repo_repo', '-1-0']
    const orgNames = ['org', 'org-name', 'org-']
    for (const repoName of repoNames) {
      for (const orgName of orgNames) {
        ssrSafeLocationMock.mockImplementation(() => ({pathname: `/${orgName}/${repoName}/issues`}))
        const url = searchUrl({viewId: VIEW_IDS.repository, query: 'state:closed'})
        expect(url).toBe(`/${orgName}/${repoName}/issues?q=${encodeURIComponent('state:closed')}`)
      }
    }
  })

  test('searchUrl returns dashboard url for invalid repo names', () => {
    const repoNames = ['|', 'new|repo', 'repo%name', '%%repo', 'repo/tt', 'repo/akenneth']
    for (const repoName of repoNames) {
      ssrSafeLocationMock.mockImplementation(() => ({pathname: `/owner/${repoName}/issues`}))
      const url = searchUrl({viewId: VIEW_IDS.repository, query: 'state:closed'})
      expect(url).toBe(`/issues?q=${encodeURIComponent('state:closed')}`)
    }
  })
})

describe('searchUrl with label URLs', () => {
  test('returns correct URL when running at label level', () => {
    ssrSafeLocationMock.mockImplementation(() => ({pathname: '/github/repo/labels/bug'}))
    const url = searchUrl({viewId: VIEW_IDS.repository, query: 'state:open label:bug'})
    expect(url).toBe(`/github/repo/issues?q=${encodeURIComponent('state:open label:bug')}`)
  })

  test('handles label URLs with special characters', () => {
    ssrSafeLocationMock.mockImplementation(() => ({pathname: '/owner/repo/labels/needs-review'}))
    const url = searchUrl({viewId: VIEW_IDS.repository, query: 'is:issue'})
    expect(url).toBe(`/owner/repo/issues?q=${encodeURIComponent('is:issue')}`)
  })

  test('returns correct URL for labels with dots and underscores', () => {
    ssrSafeLocationMock.mockImplementation(() => ({pathname: '/org/project/labels/priority.high_urgent'}))
    const url = searchUrl({viewId: VIEW_IDS.repository})
    expect(url).toBe('/org/project/issues')
  })
})

describe('issuesAtLabelShowUrl regex', () => {
  test('matches valid label URLs', () => {
    expect('/owner/repo/labels/bug'.match(issuesAtLabelShowUrl)).toBeTruthy()
    expect('/github/github/labels/enhancement'.match(issuesAtLabelShowUrl)).toBeTruthy()
    expect('/user-name/repo-name/labels/priority-high'.match(issuesAtLabelShowUrl)).toBeTruthy()
    expect('/org-123/my-repo_test/labels/needs.review'.match(issuesAtLabelShowUrl)).toBeTruthy()
  })

  test('does not match invalid label URLs', () => {
    expect('/owner/repo/issues'.match(issuesAtLabelShowUrl)).toBeFalsy()
    expect('/owner/repo/labels'.match(issuesAtLabelShowUrl)).toBeFalsy()
    expect('/owner/labels/bug'.match(issuesAtLabelShowUrl)).toBeFalsy()
    expect('/labels/bug'.match(issuesAtLabelShowUrl)).toBeFalsy()
    expect('/owner/repo/milestone/1'.match(issuesAtLabelShowUrl)).toBeFalsy()
  })

  test('extracts correct groups from label URLs', () => {
    const match = '/github/repo/labels/bug'.match(issuesAtLabelShowUrl)
    expect(match?.[1]).toBe('github') // owner
    expect(match?.[3]).toBe('repo') // repo name
    expect(match?.[5]).toBe('bug') // label name
  })
})
