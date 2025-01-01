import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DashboardLists} from '../DashboardLists'

test('Renders lists of PRs and Issues', () => {
  const pullRequests = [
    {
      id: '1',
      title: 'Update dependencies',
      permalink: 'https://github.com/github/github/pull/1',
      commentCount: 1,
      updatedAt: '2022-02-02T00:00:00Z',
    },
    {
      id: '2',
      title: 'Fix bug',
      permalink: 'https://github.com/github/github/pull/2',
      commentCount: 12,
      updatedAt: '2022-02-02T00:00:00Z',
    },
  ]

  const issues = [
    {
      id: '3',
      title: 'Bug report',
      description: 'This is a bug report',
      permalink: 'https://github.com/github/github/issues/3',
      commentCount: 0,
      comments: [],
      updatedAt: '2022-02-02T00:00:00Z',
    },
  ]

  const props = {issues, pullRequests, userDisplayLogin: 'monalisa'}

  render(<DashboardLists {...props} />)

  expect(screen.getByText('Update dependencies')).toBeInTheDocument()
  expect(screen.getByText('Fix bug')).toBeInTheDocument()
  expect(screen.getByText('Bug report')).toBeInTheDocument()
})

test('Renders empty states', () => {
  const props = {issues: [], pullRequests: [], userDisplayLogin: 'monalisa'}

  render(<DashboardLists {...props} />)

  expect(screen.getByText('No Pull Requests')).toBeInTheDocument()
  expect(screen.getByText('No Issues')).toBeInTheDocument()
})
