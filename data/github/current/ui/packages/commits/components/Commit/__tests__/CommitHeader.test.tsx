import type {SafeHTMLString} from '@github-ui/safe-html'
import {screen} from '@testing-library/react'

import {useLoadSingleDeferredCommitData} from '../../../shared/use-load-deferred-commit-data'
import {getCommitRoutePayload} from '../../../test-utils/commit-mock-data'
import {deferredCommit} from '../../../test-utils/mock-data'
import {renderCommit} from '../../../test-utils/Render'
import type {CommitPayload} from '../../../types/commit-types'
import {CommitHeader} from '../header/CommitHeader'

jest.mock('../../../shared/use-load-deferred-commit-data')
const mockedUseLoadSingleDeferredCommitData = jest.mocked(useLoadSingleDeferredCommitData)

beforeEach(() => {
  jest.clearAllMocks()
  mockedUseLoadSingleDeferredCommitData.mockReturnValue(deferredCommit)
})

test('CommitHeader contains both short message and body of the commit', async () => {
  const basePayload = getCommitRoutePayload()
  const payload: CommitPayload = {
    ...basePayload,
    commit: {...basePayload.commit, bodyMessageHtml: 'Body content' as SafeHTMLString},
  }

  renderCommit(
    <CommitHeader commit={payload.commit} commitInfo={{loading: false, branches: [], tags: []}} repo={payload.repo} />,
    payload,
  )

  expect(screen.getByText('This is a commit message')).toBeInTheDocument()
  expect(screen.getByText('Body content')).toBeInTheDocument()

  // because of jest, we can't test the scenario where we have no body but want to show the commit message
  // in the description container when we are applying CSS truncations
})

test('CommitHeader contains status badge and browse code button', async () => {
  const payload = getCommitRoutePayload()
  renderCommit(
    <CommitHeader commit={payload.commit} commitInfo={{loading: false, branches: [], tags: []}} repo={payload.repo} />,
    payload,
  )

  expect(screen.getByLabelText('Status checks: success')).toBeInTheDocument()
  expect(screen.getAllByRole('link', {name: 'Browse files'})).toHaveLength(2) // mobile and desktop viewports
})

test('CommitHeader contains the short sha and allows you to copy it', async () => {
  const payload = getCommitRoutePayload()
  renderCommit(
    <CommitHeader commit={payload.commit} commitInfo={{loading: false, branches: [], tags: []}} repo={payload.repo} />,
    payload,
  )

  // One for the large title, and one as a smaller element in the corner
  expect(screen.getAllByText('052a205', {exact: true})).toHaveLength(2)
  expect(screen.getByRole('button', {name: 'Copy full SHA for 052a205'})).toBeInTheDocument()
})

test('CommitHeader contains author and commit attribution', async () => {
  const basePayload = getCommitRoutePayload()
  const payload: CommitPayload = {
    ...basePayload,
    commit: {
      ...basePayload.commit,
      committerAttribution: true,
    },
  }
  renderCommit(
    <CommitHeader commit={payload.commit} commitInfo={{loading: false, branches: [], tags: []}} repo={payload.repo} />,
    payload,
  )

  // authors
  expect(screen.getByText('2 people')).toBeInTheDocument()
  // committer
  expect(screen.getByText('web-flow')).toBeInTheDocument()
})

test("CommitHeader doesn't show committer attribution when it's disabled", async () => {
  const payload = getCommitRoutePayload()
  renderCommit(
    <CommitHeader commit={payload.commit} commitInfo={{loading: false, branches: [], tags: []}} repo={payload.repo} />,
    payload,
  )

  // authors
  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('monalisa2')).toBeInTheDocument()
  // committer
  expect(screen.queryByText('GitHub')).not.toBeInTheDocument()
})

test('CommitHeader shows signed CommitHeader', async () => {
  const payload = getCommitRoutePayload()
  renderCommit(
    <CommitHeader commit={payload.commit} commitInfo={{loading: false, branches: [], tags: []}} repo={payload.repo} />,
    payload,
  )

  expect(screen.getByText('Verified')).toBeInTheDocument()
})

test('CommitHeader shows parent commits', async () => {
  const basePayload = getCommitRoutePayload()
  const payload: CommitPayload = {
    ...basePayload,
    commit: {
      ...basePayload.commit,
      oid: '16559b83c5986c35b2fdabcbe8f5bc0e6ffcda3b',
      parents: ['d28fac7f18aeacb00d8ad3460a0a5a901617c2d4', '6c48e85bdfa2113ed368a255ca8b8922945c5a3b'],
    },
  }

  renderCommit(
    <CommitHeader commit={payload.commit} commitInfo={{loading: false, branches: [], tags: []}} repo={payload.repo} />,
    payload,
  )

  expect(screen.getByText('2 parents', {exact: false})).toBeInTheDocument()
  expect(screen.getByText('d28fac7')).toBeInTheDocument()
  expect(screen.getByText('6c48e85')).toBeInTheDocument()
})
