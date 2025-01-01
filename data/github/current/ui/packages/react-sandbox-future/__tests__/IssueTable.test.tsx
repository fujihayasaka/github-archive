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
    render(<IssueTable issues={[]} isPending={false} />)
    expect(screen.getByText('No issues to display')).toBeInTheDocument()
  })

  it('displays issues when there are issues and isPending is false', () => {
    render(<IssueTable issues={mockIssues} isPending={false} />)
    expect(screen.getByText('Issue 1')).toBeInTheDocument()
    expect(screen.getByText('Issue 2')).toBeInTheDocument()
  })
})
