import '../../test-utils/mocks'

import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {TerminalContextProvider} from '../../contexts/TerminalContext'
import {getWorkspaceEditorRoutePayload} from '../../test-utils/mock-data'
import {TestComponentWrapper} from '../../test-utils/TestComponentWrapper'
import {Header} from '../Header'

const terminateMock = jest.fn()

// Web workers are not supported on jsdom, so we mock the minimum we need for this test,
// which will call onmessage once per each postMessage with a fixed resultset.
window.Worker = class {
  // onmessage will be replaced by the caller to handle responses
  onmessage = (data: unknown) => data
  postMessage() {
    this.onmessage({data: {query: 'any', list: ['contra', 'transport', 'ter/rain'], startTime: 20, baseCount: 4}})
  }
  terminate = terminateMock
} as unknown as typeof Worker

jest.useFakeTimers()

const reducer = jest.fn()
jest.mock('../../utilities/workspace-editor-ui-reducer', () => ({
  ...jest.requireActual('../../utilities/workspace-editor-ui-reducer'),
  workspaceEditorUIReducer: jest.fn(() => reducer),
}))
jest.mock('../../hooks/use-fetch-repo-terminal-tasks', () => ({
  useFetchRepoTerminalTasks: jest
    .fn()
    .mockReturnValue({fetchRepoTasks: () => Promise.resolve({build: 'build', test: 'test'})}),
}))

function TestComponent() {
  return (
    <TestComponentWrapper>
      <TerminalContextProvider>
        <Header
          pullRequestNumber="1"
          actionableSuggestionsCount={0}
          copilotHeaderButtonRef={{current: null}}
          commitButtonRef={{current: null}}
          forwardedUrl=""
        />
      </TerminalContextProvider>
    </TestComponentWrapper>
  )
}

describe('Header', () => {
  test('renders header', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    render(<TestComponent />, {routePayload})

    await waitFor(() => {
      expect(screen.getByText('Copilot Workspace')).toBeVisible()
    })
    await waitFor(() => {
      expect(screen.getByText('Review and commit…')).toBeVisible()
    })
  })

  test('copilot panel button', async () => {
    const routePayload = getWorkspaceEditorRoutePayload()
    const {user} = render(<TestComponent />, {routePayload})

    const copilotPanelButton = screen.getByLabelText('Toggle Copilot panel')
    expect(copilotPanelButton).toBeVisible()
    await user.click(copilotPanelButton)

    expect(reducer).toHaveBeenCalledWith(expect.anything(), {
      type: 'TOGGLE_RIGHT_PANEL',
      rightPanel: 'Chat',
      rightPanelButton: expect.anything(),
    })
  })
})
