import {render, screen} from '@testing-library/react'
import {composeStory} from '@storybook/react'
import meta, {IssueRowExample as Example} from '../IssueRow.stories'
import {IssueRowExampleWithOverrides as ExampleWithOverrides} from '../IssueRow.stories.helpers'
import {mockClientEnv} from '@github-ui/client-env/mock'

const IssueRowExample = composeStory(Example, meta)

test('renders the title', () => {
  render(<IssueRowExample />)

  expect(screen.getByText('title')).toBeInTheDocument()
})

test('renders the issue type', () => {
  render(<IssueRowExample />)

  expect(screen.getByText('Bug')).toBeInTheDocument()
})

test('uses the given method to render an href on the issue type', () => {
  render(<IssueRowExample />)

  const link = screen.getByRole('link', {name: 'Bug'})
  expect(link.getAttribute('href')).toBe('#test(type,Bug)')
})

test('renders the milestone', () => {
  render(<IssueRowExample />)

  expect(screen.getByText('milestone-1')).toBeInTheDocument()
})

test('renders the title with fallback from titleHtml', () => {
  const Story = composeStory(ExampleWithOverrides('title', ''), meta)
  render(<Story />)

  const titleLink = screen.getByTestId('issue-pr-title-link')
  expect(titleLink).toBeInTheDocument()

  expect(titleLink.textContent).toBe('title')
})

test('does not render the title when fallback from titleHtml is prohibited', () => {
  mockClientEnv({
    featureFlags: ['issues_react_prohibit_title_fallback'],
  })

  const Story = composeStory(ExampleWithOverrides('title', ''), meta)
  render(<Story />)

  const titleLink = screen.getByTestId('issue-pr-title-link')
  expect(titleLink).toBeInTheDocument()

  expect(titleLink).toBeEmptyDOMElement()
})
