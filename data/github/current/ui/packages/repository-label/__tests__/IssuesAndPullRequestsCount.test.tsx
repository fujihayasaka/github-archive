import type {IssuesAndPullRequestsCountSecondaryQuery} from '../__generated__/IssuesAndPullRequestsCountSecondaryQuery.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {IssuesAndPullRequestsCountInternal} from '../IssuesAndPullRequestsCount'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {DescriptionProvider} from '@github-ui/list-view/ListItemDescriptionContext'

const renderIssuesAndPullRequestsCount = () => {
  return renderRelay<{secondaryDataQuery: IssuesAndPullRequestsCountSecondaryQuery}>(
    ({queryData: {secondaryDataQuery}}) => {
      if (!secondaryDataQuery) {
        return null
      }

      if (!secondaryDataQuery.nodes[0]) {
        return null
      }

      return (
        <Wrapper>
          <VariantProvider>
            <DescriptionProvider>
              <IssuesAndPullRequestsCountInternal
                labelName="mockLabelName"
                labelNode={secondaryDataQuery.nodes[0]}
                repositoryNameWithOwner="github/github"
              />
            </DescriptionProvider>
          </VariantProvider>
        </Wrapper>
      )
    },
    {
      relay: {
        queries: {
          secondaryDataQuery: {
            type: 'fragment',
            query: graphql`
              query IssuesAndPullRequestsCountSecondaryTestQuery @relay_test_operation {
                nodes(ids: ["123"]) {
                  ... on Label {
                    ...IssuesAndPullRequestsCount @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {
              nodes: ['issueId'],
            },
          },
        },
        mockResolvers: {
          Label: () => ({
            id: 'mockId',
            issueCount: 12,
            pullRequestCount: 4,
          }),
        },
      },
    },
  )
}

describe('Issues and pull request count of a label', () => {
  test('renders issues and pull requests counts', () => {
    renderIssuesAndPullRequestsCount()

    expect(screen.getByRole('link', {name: /12 open issues/})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /4 open pull requests/})).toBeInTheDocument()
  })

  test('have the correct href for open issues and pull requests to navigate', () => {
    renderIssuesAndPullRequestsCount()
    const openIssuesLink = screen.getByRole('link', {name: /12 open issues/})
    expect(openIssuesLink).toHaveAttribute(
      'href',
      '/github/github/issues?q=is%3Aopen%20is%3Aissue%20label%3A%22mockLabelName%22',
    )
    const openPullRequests = screen.getByRole('link', {name: /4 open pull requests/})
    expect(openPullRequests).toHaveAttribute(
      'href',
      '/github/github/issues?q=is%3Aopen%20is%3Apr%20label%3A%22mockLabelName%22',
    )
  })
})
