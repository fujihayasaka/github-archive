import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {IssueTable} from '../components/IssueTable'
import type {DashboardIssue} from '../data-types'

const mockIssues: DashboardIssue[] = [
  {id: '1', title: 'Issue 1', state: 'open', url: '/issue/1'},
  {id: '2', title: 'Issue 2', state: 'closed', url: '/issue/2'},
]

describe('IssueTable', () => {
  it('displays a skeleton when isPending is true', () => {
    render(<IssueTable issues={[]} isPending />)
    expect(screen.getAllByRole('cell', {name: 'Loading'})[0]).toBeInTheDocument()
  })

  it('displays a blankslate when there are no issues and isPending is false', () => {
    render(<IssueTable issues={[]} />)
    expect(screen.getByText('No items to display')).toBeInTheDocument()
  })

  it('displays issues when there are issues and isPending is false', () => {
    render(<IssueTable issues={mockIssues} />)
    expect(screen.getByText('Issue 1')).toBeInTheDocument()
    expect(screen.getByText('Issue 2')).toBeInTheDocument()
  })

  it('shows an error dialog when isError is true', async () => {
    const onRetry = jest.fn()
    const {user} = render(<IssueTable issues={mockIssues} isError onRetry={onRetry} />)
    expect(screen.getByRole('heading', {name: 'Error'})).toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Retry'}))
    expect(onRetry).toHaveBeenCalled()

    await user.click(screen.getByRole('button', {name: 'Dismiss'}))
    expect(screen.queryByRole('heading', {name: 'Error'})).not.toBeInTheDocument()
  })
})
