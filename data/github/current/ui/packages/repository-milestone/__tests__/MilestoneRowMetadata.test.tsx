import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneRowMetadata} from '../MilestoneRowMetadata'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import {Wrapper} from '@github-ui/react-core/test-utils'

import type {MilestoneRowMetadataQuery} from './__generated__/MilestoneRowMetadataQuery.graphql'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'
import type {MockResolverContext} from 'relay-test-utils/lib/RelayMockPayloadGenerator'

describe('MilestoneRowMetadata', () => {
  test('renders milestone row', () => {
    renderRelay<{milestoneQuery: MilestoneRowMetadataQuery}>(
      ({queryData: {milestoneQuery}}) => (
        <Wrapper>
          <IdProvider>
            <VariantProvider>
              <TitleProvider title="milestone row">
                <MilestoneRowMetadata milestone={milestoneQuery.node!} repositoryNameWithOwner="github/github" />
              </TitleProvider>
            </VariantProvider>
          </IdProvider>
        </Wrapper>
      ),
      {
        relay: {
          queries: {
            milestoneQuery: {
              type: 'fragment',
              query: graphql`
                query MilestoneRowMetadataQuery @relay_test_operation {
                  node(id: "123") {
                    ... on Milestone {
                      ...MilestoneRowMetadata @dangerously_unaliased_fixme
                    }
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            Milestone: () => ({
              title: 'release',
              description: 'next version',
            }),
            Int: (context: MockResolverContext) => {
              if (context.name === 'openIssueCount') {
                return 3
              }
              if (context.name === 'closedIssueCount') {
                return 7
              }
              return 1
            },
            Float: (context: MockResolverContext) => {
              if (context.name === 'progressPercentage') {
                return 70.0
              }
              return 1.0
            },
          },
        },
      },
    )

    const progressBar = screen.getByTestId('milestone-metadata-progress-bar')
    expect(progressBar).toBeInTheDocument()

    // Find the open and closed issue links by their hrefs and text
    const openLink = screen.getByRole('link', {
      name: /open$/,
    })
    expect(openLink).toBeInTheDocument()

    // Verify that the open link includes the repository name and owner
    expect(openLink).toHaveAttribute('href', '/github/github/issues?q=is%3Aopen%20milestone%3A%22release%22')

    const closedLink = screen.getByRole('link', {
      name: /closed$/,
    })
    expect(closedLink).toBeInTheDocument()

    // Verify that the closed link includes the repository name and owner
    expect(closedLink).toHaveAttribute('href', '/github/github/issues?q=is%3Aclosed%20milestone%3A%22release%22')
  })
})
