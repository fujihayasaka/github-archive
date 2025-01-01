import {render} from '@github-ui/react-core/test-utils'
import {CopilotFreeUserChecklist} from '../CopilotFreeUserChecklist'
import {getCopilotFreeUserChecklistProps} from '../test-utils/mock-data'
import {screen} from '@testing-library/react'
import {sendEvent} from '@github-ui/hydro-analytics'

jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn(),
}))

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

afterEach(() => {
  jest.clearAllMocks()
  sessionStorage.clear()
})

test('Renders the CopilotFreeUserChecklist', () => {
  const props = getCopilotFreeUserChecklistProps()
  render(<CopilotFreeUserChecklist {...props} />)
  expect(screen.getByText('Install Copilot in your editor')).toBeInTheDocument()
  expect(screen.getByText('Start building with Copilot')).toBeInTheDocument()
  expect(screen.getByText('Chat with Copilot anywhere')).toBeInTheDocument()
  expect(sendEvent).toHaveBeenCalledWith('copilot.free_user_checklist.view', undefined)
})

test('Handles dismiss action', async () => {
  const props = getCopilotFreeUserChecklistProps()
  const {user} = render(<CopilotFreeUserChecklist {...props} />)

  expect(screen.getByText('Install Copilot in your editor')).toBeInTheDocument()
  const menuButton = screen.getByTestId('checklist-options')
  await user.click(menuButton)

  expect(screen.getByText('Remove')).toBeInTheDocument()
  const removeButton = screen.getByTestId('checklist-remove-option')
  await user.click(removeButton)
  expect(screen.queryByText('Install Copilot in your editor')).not.toBeInTheDocument()

  expect(sendEvent).toHaveBeenCalledWith('copilot.free_user_checklist.dismiss', undefined)
})

test('Handles checklist item completion', async () => {
  const props = {
    ...getCopilotFreeUserChecklistProps(),
    checklistState: [false, false, false],
  }
  const {user} = render(<CopilotFreeUserChecklist {...props} />)

  expect(screen.getByText('Install Copilot in your editor')).toBeInTheDocument()
  expect(screen.getByTestId('stepper-step-0-unchecked')).toBeInTheDocument()

  const menuButton = screen.getByTestId('editor-dropdown-button')
  await user.click(menuButton)

  const vscode = screen.getByRole('menuitem', {name: 'Visual Studio Code'})
  await user.click(vscode)

  expect(screen.getByTestId('stepper-step-0-checked')).toBeInTheDocument()
  expect(sendEvent).toHaveBeenCalledWith('copilot.free_user_checklist.step_complete', {step: 1})
  expect(sendEvent).not.toHaveBeenCalledWith('copilot.free_user_checklist.completed', undefined)
})

test('Track completion of all steps', async () => {
  const props = {
    ...getCopilotFreeUserChecklistProps(),
    checklistState: [true, true, false],
  }
  const {user} = render(<CopilotFreeUserChecklist {...props} />)

  const button = screen.getByText('Get started')
  expect(button).toBeInTheDocument()
  await user.click(button)

  expect(sendEvent).toHaveBeenCalledWith('copilot.free_user_checklist.step_complete', {step: 3})
  expect(sendEvent).toHaveBeenCalledWith('copilot.free_user_checklist.completed', undefined)
})

test('Handles error when session storage JSON cannot be parsed', () => {
  jest.spyOn(console, 'error').mockImplementation()
  const props = {
    ...getCopilotFreeUserChecklistProps(),
    checklistState: [true, true, false],
  }
  const invalidSessionStorageValue = 'invalid JSON'
  sessionStorage.setItem('copilot_settings_free_user_checklist', invalidSessionStorageValue)

  expect(() => render(<CopilotFreeUserChecklist {...props} />)).toThrow(
    'free user checklist: failed to parse session storage data',
  )

  expect(screen.queryByText('Install Copilot in your editor')).not.toBeInTheDocument()
})

test('Icebreaker click triggers step completion', async () => {
  const props = {
    ...getCopilotFreeUserChecklistProps(),
    checklistState: [true, false, false],
  }
  const {user} = render(<CopilotFreeUserChecklist {...props} />)

  const link = screen.getByTestId('free-checklist-icebreaker-link')
  expect(link).toBeInTheDocument()
  await user.click(link)

  expect(screen.getByTestId('stepper-step-1-checked')).toBeInTheDocument()
  expect(sendEvent).toHaveBeenCalledWith('copilot.free_user_checklist.step_complete', {step: 2})
})
