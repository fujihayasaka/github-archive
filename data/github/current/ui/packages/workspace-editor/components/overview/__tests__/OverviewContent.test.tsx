import '../../../test-utils/mocks'

import {mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useRef} from 'react'

import {
  getCategorizedDiffsPayload,
  getWorkspaceEditorOverviewPayload,
  getWorkspaceEditorRoutePayload,
} from '../../../test-utils/mock-data'
import {TestComponentWrapper} from '../../../test-utils/TestComponentWrapper'
import {OverviewContent} from '../OverviewContent'

function TestComponent() {
  const terminalHeaderButtonRef = useRef<HTMLButtonElement>(null)
  return (
    <TestComponentWrapper>
      <OverviewContent
        codespaceData={{
          codespaceInfo: null,
          codespaceState: 'none',
          workspaceRoot: 'workspaceRoot',
          isRecoveryContainer: false,
          recreateCodespace: () => {},
          pollForPermissionsAccepted: () => {},
        }}
        isTreeExpanded={false}
        terminalHeaderButtonRef={terminalHeaderButtonRef}
        onDetailsClick={() => {}}
        onTerminalClick={() => {}}
        treeToggleElement={<></>}
      />
    </TestComponentWrapper>
  )
}

test('renders overview content', async () => {
  mockFetch.mockRouteOnce('/monalisa/smile/pull/1/edit/overview', getWorkspaceEditorOverviewPayload())

  render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload()})

  expect(await screen.findByText('PR title')).toBeVisible()
  expect(await screen.findByText('PR body')).toBeVisible()
  expect(await screen.findByText('my label')).toBeVisible()

  const prLink = screen.getByRole('link', {name: /#1/i})
  expect(prLink).toBeVisible()
  expect(prLink).toHaveAttribute('href', expect.stringContaining('/monalisa/smile/pull/1'))

  expect(screen.getByText('feature-branch')).toBeVisible()
  expect(screen.getByText('main')).toBeVisible()
})

test('renders overview diffs', async () => {
  mockFetch.mockRouteOnce('/monalisa/smile/pull/1/edit/overview', getWorkspaceEditorOverviewPayload())
  mockFetch.mockRouteOnce(
    '/monalisa/smile/pull/1/diff?analyze_diffs=true&detect_risk=false',
    getCategorizedDiffsPayload(),
  )

  const {user} = render(<TestComponent />, {routePayload: getWorkspaceEditorRoutePayload()})

  expect(await screen.findByText('Code')).toBeVisible()
  const toggleCollapsedFile = screen.getByLabelText('expand file: readme.md')
  expect(toggleCollapsedFile).toBeVisible()
  await user.click(toggleCollapsedFile)

  expect(await screen.findByText('This is the original line')).toBeVisible()
  expect(await screen.findByText('This line is unchanged')).toBeVisible()
})
