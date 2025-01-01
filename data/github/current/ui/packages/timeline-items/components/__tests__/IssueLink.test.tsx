import {graphql} from 'relay-runtime'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import type {IssueLinkTestQuery} from './__generated__/IssueLinkTestQuery.graphql'
import {IssueLink} from '../IssueLink'

test('Renders issue title', () => {
  setup({}, '')

  expect(screen.getByText('issue title')).toBeInTheDocument()
})

test('Renders issue number when source and target are in the same repository', () => {
  setup({}, '111')

  expect(screen.getByText('#123')).toBeInTheDocument()
})

test('Renders repository nwo when source and target are in different repositories', () => {
  setup({}, '222')

  expect(screen.getByText('github/smile#123')).toBeInTheDocument()

  const lock = screen.queryByRole('tooltip', {name: 'Only people who can see github/smile will see this reference.'})
  expect(lock).not.toBeInTheDocument()
})

test('Renders lock when source and target are in different repositories and source is private', () => {
  setup(
    {
      repository: {
        id: '111',
        owner: {
          login: 'github',
        },
        name: 'smile',
        isPrivate: true,
      },
    },
    '222',
  )

  expect(screen.getByText('github/smile#123')).toBeInTheDocument()

  const lock = screen.queryByRole('tooltip', {name: 'Only people who can see github/smile will see this reference.'})
  expect(lock).toBeInTheDocument()
})

test('Does not render lock when source and target are in different repositories and source is not private', () => {
  setup(
    {
      repository: {
        id: '111',
        owner: {
          login: 'github',
        },
        name: 'smile',
        isPrivate: false,
      },
    },
    '222',
  )

  expect(screen.getByText('github/smile#123')).toBeInTheDocument()

  const lock = screen.queryByRole('tooltip', {name: 'Only people who can see github/smile will see this reference.'})
  expect(lock).not.toBeInTheDocument()
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function setup(resolverOverrides: any = {}, targetRepositoryId: string) {
  renderRelay<{query: IssueLinkTestQuery}>(
    ({queryData}) => <IssueLink data={queryData.query.node!} targetRepositoryId={targetRepositoryId} />,
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query IssueLinkTestQuery @relay_test_operation {
                node(id: "node-id") {
                  ... on Issue {
                    ...IssueLink @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              issueTitleHTML: 'issue title',
              number: 123,
              repository: {
                id: '111',
                owner: {
                  login: 'github',
                },
                name: 'smile',
              },
              ...resolverOverrides,
            }
          },
        },
      },
    },
  )
}
