import {renderRelay} from '@github-ui/relay-test-utils'
import ISSUE_NEW_CHOOSE_QUERY from '../issue-new/__generated__/IssueRepoNewChoosePageQuery.graphql'
import {IssueRepoNewChoosePageContent} from '../issue-new/IssueRepoNewChoosePage'
import type {IssueRepoNewChoosePageQuery} from '../issue-new/__generated__/IssueRepoNewChoosePageQuery.graphql'

jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  ssrSafeWindow: {
    ...jest.requireActual('@github-ui/ssr-utils').ssrSafeWindow,
    location: {
      search: 'template=bug-01.md',
      pathname: '/new/choose',
    },
  },
}))

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

function setup() {
  return renderRelay<{
    newChoosePageQuery: IssueRepoNewChoosePageQuery
  }>(({queryRefs: {newChoosePageQuery}}) => <IssueRepoNewChoosePageContent pageQueryRef={newChoosePageQuery} />, {
    relay: {
      queries: {
        newChoosePageQuery: {
          type: 'preloaded',
          query: ISSUE_NEW_CHOOSE_QUERY,
          variables: {name: 'some', owner: 'owner'},
        },
      },
      mockResolvers: {
        Repository() {
          return {
            name: 'some',
          }
        },
      },
    },
  })
}

describe('IssueRepoNewChoosePage', () => {
  test('does not do a client redirect', () => {
    setup()
    // redirect happens on the server
    expect(navigateFn).not.toHaveBeenCalled()
  })
})
