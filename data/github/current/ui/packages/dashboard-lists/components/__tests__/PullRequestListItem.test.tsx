import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ListView} from '@github-ui/list-view'
import {PullRequestListItem} from '../PullRequestListItem'
import type {DashboardPullRequest} from '../../types'

const basePullRequest: DashboardPullRequest = {
  id: '1',
  title: 'Update dependencies',
  number: 1,
  permalink: 'https://github.com/github/github/pull/1',
  commentCount: 3,
  updatedAt: '2022-02-02T00:00:00Z',
  suggestedAction: 'Request reviewers',
  headSha: 'abc123',
  repoNameWithOwner: {
    ownerLogin: 'github',
    name: 'github',
  },
  inMergeQueue: false,
  isDraft: false,
  author: 'fauxnalisa',
}

describe('PullRequestListItem', () => {
  function renderWithListView(ui: React.ReactNode) {
    return render(
      <ListView title="Test" ariaLabelledBy="test-heading">
        {ui}
      </ListView>,
    )
  }

  it('renders pull request title', () => {
    renderWithListView(<PullRequestListItem pullRequest={basePullRequest} onTitleClick={() => {}} />)
    expect(screen.getByText('Update dependencies')).toBeInTheDocument()
  })

  it('renders the repo with owner, pull request number, and author', () => {
    renderWithListView(<PullRequestListItem pullRequest={basePullRequest} onTitleClick={() => {}} />)
    expect(screen.getByText('github/github#1 · Opened by fauxnalisa')).toBeInTheDocument()
  })

  it('renders suggested action label', () => {
    renderWithListView(<PullRequestListItem pullRequest={basePullRequest} onTitleClick={() => {}} />)
    expect(screen.getByText('Request reviewers')).toBeInTheDocument()
  })

  it('renders comment count', () => {
    renderWithListView(<PullRequestListItem pullRequest={basePullRequest} onTitleClick={() => {}} />)
    expect(screen.getByText('3')).toBeInTheDocument()
  })

  it('renders merge queue icon if inMergeQueue is true', () => {
    const pr = {...basePullRequest, inMergeQueue: true}
    renderWithListView(<PullRequestListItem pullRequest={pr} onTitleClick={() => {}} />)
    expect(screen.getByTestId('icon-merge-queue')).toBeInTheDocument()
  })

  it('renders draft icon if isDraft is true', () => {
    const pr = {...basePullRequest, isDraft: true}
    renderWithListView(<PullRequestListItem pullRequest={pr} onTitleClick={() => {}} />)
    expect(screen.getByTestId('icon-pull-request-draft')).toBeInTheDocument()
  })
})
