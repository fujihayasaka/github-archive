import {screen} from '@testing-library/react'
import {ThemeProvider} from '@primer/react'

import {ISSUE_VIEWER_DEFAULT_CONFIG} from '../../OptionConfig'
import {HeaderViewer, type HeaderViewerProps} from '../HeaderViewer'
import {graphql} from 'react-relay'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {HeaderViewerTestQuery, HeaderViewerTestQuery$data} from './__generated__/HeaderViewerTestQuery.graphql'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {noop} from '@github-ui/noop'

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

const query = graphql`
  query HeaderViewerTestQuery @relay_test_operation {
    node(id: "issue1") {
      ...HeaderViewer
    }
  }
`
interface TestComponentProps {
  issue: HeaderViewerTestQuery$data
  overrides?: Partial<HeaderViewerProps>
}
function TestComponent({issue, overrides}: TestComponentProps) {
  return (
    <ThemeProvider>
      <HeaderViewer
        optionConfig={{
          ...ISSUE_VIEWER_DEFAULT_CONFIG,
          customEditMenuEntries: [<li key="1">Cool action 1</li>, <li key="2">Cool action 2</li>],
          showIssueCreateButton: true,
        }}
        headerViewerKey={issue.node!}
        {...overrides}
      />
    </ThemeProvider>
  )
}

const mockIssue = {
  id: mockRelayId(),
  titleHTML: 'Fix it',
  number: 42,
}

test('Renders the title', async () => {
  renderRelay<{
    issue: HeaderViewerTestQuery
  }>(({queryData: {issue}}) => <TestComponent issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return mockIssue
        },
      },
    },
  })
  expect(screen.getByText(mockIssue.titleHTML)).toBeInTheDocument()
})

test('Renders issue number as plain text', async () => {
  renderRelay<{
    issue: HeaderViewerTestQuery
  }>(({queryData: {issue}}) => <TestComponent issue={issue} />, {
    relay: {
      queries: {
        issue: {
          type: 'fragment',
          query,
          variables: {},
        },
      },
      mockResolvers: {
        Issue() {
          return mockIssue
        },
      },
    },
  })
  expect(screen.getByText(`#${mockIssue.number}`)).toBeInTheDocument()
  expect(screen.queryByRole('link', {name: `#${mockIssue.number}`})).not.toBeInTheDocument()
})

test('Renders number as link in a sidepanel', async () => {
  renderRelay<{
    issue: HeaderViewerTestQuery
  }>(
    ({queryData: {issue}}) => (
      <TestComponent issue={issue} overrides={{optionConfig: {insideSidePanel: true, navigate: noop}}} />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return mockIssue
          },
        },
      },
    },
  )
  expect(screen.getByRole('link', {name: `#${mockIssue.number}`})).toBeVisible()
})
