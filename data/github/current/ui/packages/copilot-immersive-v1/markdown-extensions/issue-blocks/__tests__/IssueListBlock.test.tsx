import {render as renderWithoutWrapper} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ListBlock} from '../IssueListBlock'
import {Wrapper} from '../test-utils/Wrapper'

function render(ui: React.ReactElement) {
  return renderWithoutWrapper(ui, {wrapper: Wrapper})
}

describe('ListBlock', () => {
  jest.useFakeTimers().setSystemTime(new Date('2025-03-10T01:00:00Z'))

  it('renders a complete issue', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming={false}
        data={`
data:
- url: "https://github.com/primer/react/issues/5753"
  state: "open"
  draft: false
  title: "Release Tracking"
  number: 5753
  created_at: "2025-03-10T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels: []
  author: "github-actions[bot]"
  comments: 0
  assignees_avatar_urls:
    - "https://avatars.githubusercontent.com/in/15368?v=4"
`}
      />,
    )

    expect(screen.getByRole('link', {name: 'Release Tracking #5753'})).toBeInTheDocument()
    // relative-time doesn't seem to work in JSDom even with fake timers
    expect(screen.getByText(/github-actions\[bot\]\s+opened/)).toBeInTheDocument()
    expect(screen.getByRole('img', {name: '1 assignee'})).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'Open issue'})).toBeInTheDocument()
  })

  it('shows nothing when streaming', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming
        data={`
data:
-
`}
      />,
    )

    expect(screen.queryByRole('link', {name: 'Unknown issue'})).not.toBeInTheDocument()
  })

  it('does not crash on invalid date', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming={false}
        data={`
data:
- url: "https://github.com/primer/react/issues/5753"
  state: "open"
  draft: false
  title: "Invalid Date Test"
  number: 5753
  created_at: "invalid-date"
  closed_at: ""
  merged_at: ""
  labels: []
  author: "test-user"
  comments: 0
  assignees_avatar_urls: []
`}
      />,
    )

    expect(screen.getByRole('link', {name: 'Invalid Date Test #5753'})).toBeInTheDocument()
    expect(screen.getByText(/test-user\s+opened/)).toBeInTheDocument()
  })

  it('does not crash on invalid URL', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming={false}
        data={`
data:
- url: "invalid-url"
  state: "open"
  draft: false
  title: "Invalid URL Test"
  number: 5753
  created_at: "2025-03-10T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels: []
  author: "test-user"
  comments: 0
  assignees_avatar_urls: []
`}
      />,
    )

    expect(screen.getByText('Invalid URL Test')).toBeInTheDocument()
    expect(screen.getByText(/test-user\s+opened/)).toBeInTheDocument()
  })

  it('does not crash on invalid issue number', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming={false}
        data={`
data:
- url: "https://github.com/primer/react/issues/invalid"
  state: "open"
  draft: false
  title: "Invalid Issue Number Test"
  number: invalid
  created_at: "2025-03-10T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels: []
  author: "test-user"
  comments: 0
  assignees_avatar_urls: []
`}
      />,
    )

    expect(screen.getByText('Invalid Issue Number Test')).toBeInTheDocument()
  })

  it('does not crash on invalid YAML', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming={false}
        data={`
data:
 - invalid-yaml
`}
      />,
    )

    expect(screen.getByText('Unknown issue')).toBeInTheDocument()
  })

  it('capitalizes the action when no author is present', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming={false}
        data={`
data:
- url: "https://github.com/primer/react/issues/5753"
  state: "open"
  draft: false
  title: "No Assignee Test"
  number: 5753
  created_at: "2025-03-10T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels: []
  comments: 0
  assignees_avatar_urls: []
`}
      />,
    )

    expect(screen.getByText(/Opened/)).toBeInTheDocument()
  })

  it('renders issue number as title when no title is present', () => {
    render(
      <ListBlock
        type="issue"
        isStreaming={false}
        data={`
data:
- url: "https://github.com/primer/react/issues/5753"
  state: "open"
  draft: false
  title: ""
  number: 5753
  created_at: "2025-03-10T00:00:00Z"
  closed_at: ""
  merged_at: ""
  labels: []
  author: "test-user"
  comments: 0
  assignees_avatar_urls: []
`}
      />,
    )

    expect(screen.getByRole('link', {name: '#5753'})).toBeInTheDocument()
  })
})
