import {noop} from '@github-ui/noop'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {useFeatureFlag, useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {renderRelay} from '@github-ui/relay-test-utils'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import {act, screen} from '@testing-library/react'
import {fetchQuery, graphql, Observable} from 'relay-runtime'

import {IssueBody} from '../IssueBody'
import {commitUpdateIssueBodyMutation} from '../mutations/update-issue-body-mutation'
import type {IssueBodyTestQuery} from './__generated__/IssueBodyTestQuery.graphql'

const useSessionStorageMock = useSessionStorage as jest.Mock
jest.mock('@github-ui/use-safe-storage/session-storage', () => ({
  useSessionStorage: jest.fn(),
}))

jest.mock('../mutations/update-issue-body-mutation')
const mockedUpdateIssueMutation = jest.mocked(commitUpdateIssueBodyMutation)

jest.setTimeout(10_000)

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)
const mockUseFeatureFlags = jest.mocked(useFeatureFlags)

beforeEach(() => {
  mockUseFeatureFlags.mockReturnValue({})
})

const QUERY = graphql`
  query IssueBodyTestQuery @relay_test_operation {
    repository(owner: "owner", name: "repo") {
      issue(number: 33) {
        ...IssueBody
      }
    }
  }
`

test('issue body uses presaved content over database content', async () => {
  useSessionStorageMock.mockReturnValue(['PRESAVED_CONTENT', jest.fn()])

  const {user} = renderRelay<{issueBody: IssueBodyTestQuery}>(
    ({queryData}) => <IssueBody issue={queryData.issueBody.repository!.issue!} onCommentReply={noop} />,
    {
      relay: {
        queries: {
          issueBody: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => ({
            body: 'DATABASE_CONTENT',
            viewerCanUpdateNext: true,
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  const actionsButton = screen.getByRole('button', {name: 'Issue body actions'})
  await user.click(actionsButton)

  const editButton = screen.getByRole('button', {name: 'Edit'})
  await user.click(editButton)

  const textarea = screen.getByRole('textbox', {name: 'Markdown value'})
  expect(textarea).toHaveValue('PRESAVED_CONTENT')

  const saveButton = screen.getByRole('button', {name: 'Save'})
  await user.click(saveButton)

  expect(mockedUpdateIssueMutation).toHaveBeenCalledWith(
    expect.objectContaining({
      input: expect.objectContaining({
        body: 'PRESAVED_CONTENT',
      }),
    }),
  )
})

// Mock fetchQuery
jest.mock('relay-runtime', () => ({
  ...jest.requireActual('relay-runtime'),
  fetchQuery: jest.fn(),
}))

test('refetchHtml is called after hover', async () => {
  jest.useFakeTimers()
  mockUseFeatureFlag.mockReturnValue(true)
  useSessionStorageMock.mockReturnValue(['PRESAVED_CONTENT', jest.fn()])
  const mathAbsSpy = jest.spyOn(Math, 'abs')

  const mockResponse = {
    node: {
      body: '<video role="video" src="new-test" />',
      bodyHTML: '<video role="video" src="new-test" />',
    },
  }

  // Mock fetchQuery to return a RelayObservable
  ;(fetchQuery as jest.Mock).mockImplementation(() =>
    Observable.create(sink => {
      sink.next(mockResponse)
      sink.complete()
    }),
  )

  const {user} = renderRelay<{issueBody: IssueBodyTestQuery}>(
    ({queryData}) => <IssueBody issue={queryData.issueBody.repository!.issue!} onCommentReply={noop} />,
    {
      relay: {
        queries: {
          issueBody: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => ({
            body: '<video role="video" src="test" />',
            bodyHTML: '<video role="video" src="test" />',
            viewerCanUpdateNext: true,
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  // Go 60 minutes into the future, we shouldn't trigger a refetch however till the user does something
  await act(async () => jest.advanceTimersByTime(260 * 60 * 1000))
  expect(fetchQuery).not.toHaveBeenCalled()

  // User mouses over the body
  const body = screen.getByTestId('markdown-body')
  await user.hover(body)
  // Test the debounced method is called
  expect(mathAbsSpy).toHaveBeenCalled()

  // The updated body is fetched and the src tags updated - and only called once
  expect(fetchQuery).toHaveBeenCalledTimes(1)

  // Check the src of the video has been updated
  const src = screen.getByRole('video').getAttribute('src')
  expect(src).toBe('new-test')

  // Wait for 2 seconds
  await act(async () => jest.advanceTimersByTime(2000))

  mathAbsSpy.mockRestore()
  await user.hover(screen.getByTestId('markdown-body'))
  expect(mathAbsSpy).not.toHaveBeenCalled()
})
