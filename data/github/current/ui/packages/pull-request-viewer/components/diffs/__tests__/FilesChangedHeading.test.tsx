import {buildComment} from '@github-ui/conversations/test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'
import {graphql, useLazyLoadQuery} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {PullRequestContextProvider} from '../../../contexts/PullRequestContext'
import {PullRequestMarkersDialogContextProvider} from '../../../contexts/PullRequestMarkersContext'
import PullRequestsAppWrapper from '../../../test-utils/PullRequestsAppWrapper'
import {buildReviewThread} from '../../../test-utils/query-data'
import {buildPullRequest, type PullRequestThread} from '../../../test-utils/query-data'
import FilesChangedHeading from '../FilesChangedHeading'
import type {FilesChangedHeadingTestQuery} from './__generated__/FilesChangedHeadingTestQuery.graphql'

interface TestComponentProps {
  environment: ReturnType<typeof createMockEnvironment>
  pullRequestId?: string
}

function TestComponent({environment, pullRequestId = 'PR_kwAEAg'}: TestComponentProps) {
  const FilesChangedHeadingWithRelayQuery = () => {
    const data = useLazyLoadQuery<FilesChangedHeadingTestQuery>(
      graphql`
        query FilesChangedHeadingTestQuery(
          $pullRequestId: ID!
          $startOid: String
          $endOid: String
          $singleCommitOid: String
        ) @relay_test_operation {
          pullRequest: node(id: $pullRequestId) {
            ... on PullRequest {
              ...FilesChangedHeading_pullRequest
            }
          }
          viewer {
            ...FilesChangedHeading_viewer
          }
        }
      `,
      {
        pullRequestId,
      },
    )

    if (data.pullRequest) {
      return <FilesChangedHeading pullRequest={data.pullRequest} viewer={data.viewer} />
    }
    return null
  }

  return (
    <PullRequestsAppWrapper environment={environment} pullRequestId={pullRequestId}>
      <PullRequestContextProvider
        headRefOid="mock"
        isInMergeQueue={false}
        pullRequestId={pullRequestId}
        repositoryId="mock"
        state="OPEN"
      >
        <PullRequestMarkersDialogContextProvider
          annotationMap={{}}
          diffAnnotations={[]}
          filteredFiles={new Set()}
          setGlobalMarkerNavigationState={jest.fn()}
          threads={[]}
        >
          <FilesChangedHeadingWithRelayQuery />
        </PullRequestMarkersDialogContextProvider>
      </PullRequestContextProvider>
    </PullRequestsAppWrapper>
  )
}

describe('comparison data', () => {
  test('shows the comparison data', async () => {
    const environment = createMockEnvironment()
    render(<TestComponent environment={environment} />)

    // eslint-disable-next-line @typescript-eslint/require-await
    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation =>
        MockPayloadGenerator.generate(operation, {
          PullRequest() {
            return buildPullRequest({comparison: {linesAdded: 13, linesChanged: 5, linesDeleted: 28}})
          },
        }),
      )
    })
    expect(screen.getByText('+13')).toBeInTheDocument()
    expect(screen.getByText('-28')).toBeInTheDocument()
    expect(screen.queryByText('5')).not.toBeInTheDocument()
  })
})

describe('diff view settings', () => {
  test('shows the diff view settings button', async () => {
    const environment = createMockEnvironment()
    render(<TestComponent environment={environment} />)

    // eslint-disable-next-line @typescript-eslint/require-await
    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation =>
        MockPayloadGenerator.generate(operation, {
          PullRequest() {
            return buildPullRequest()
          },
        }),
      )
    })

    expect(screen.getByLabelText('Diff view settings')).toBeInTheDocument()
  })
})

describe('Comments button', () => {
  // TODO: Figure out how to load data when component is calling another preloaded query
  test.skip('renders the CommentsSidesheet when clicked', async () => {
    const environment = createMockEnvironment()
    const {user} = render(<TestComponent environment={environment} />)

    const comment1 = buildComment({
      bodyHTML: 'test comment',
    })

    const thread1 = buildReviewThread({
      firstComment: comment1,
      threadPreviewComments: [comment1],
    })

    // get comments button
    const commentsButton = await screen.findByLabelText('Open comments side panel')
    expect(commentsButton).toBeInTheDocument()

    // eslint-disable-next-line @typescript-eslint/require-await
    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation =>
        MockPayloadGenerator.generate(operation, {
          PullRequest() {
            return buildPullRequest({
              allThreads: {threads: [thread1 as unknown as PullRequestThread], totalCommentsCount: 1},
            })
          },
        }),
      )
    })

    // click the comments button
    await user.click(commentsButton)

    // get comments sidesheet
    const commentsSidesheet = await screen.findByLabelText('Threads')
    expect(commentsSidesheet).toBeInTheDocument()
  })
})
