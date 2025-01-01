import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ChatStateProvider, CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {render} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor} from '@testing-library/react'

import {GitHubUrlDialog} from '../GitHubUrlDialog'
import {useValidateUrlResources} from '../hooks/use-validate-url-resources'

// Mock the useValidateUrlResources hook
jest.mock('../hooks/use-validate-url-resources', () => ({
  useValidateUrlResources: jest.fn(),
  UrlDetails: jest.requireActual('../hooks/use-validate-url-resources').UrlDetails,
}))

// Helper function to create a wrapper component with state management
function createTestWrapper(customCopilot: CustomCopilot) {
  const initialState = {
    ...getDefaultReducerState(null, undefined, 'immersive'),
    customCopilots: [customCopilot],
    threads: new Map(),
  }

  return function TestWrapper({owner}: {owner?: string}) {
    return (
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} mode="immersive">
        <ChatStateProvider state={initialState}>
          <GitHubUrlDialog onSave={() => {}} onClose={() => {}} owner={owner} />
        </ChatStateProvider>
      </CopilotChatProvider>
    )
  }
}

describe('GitHubUrlDialog', () => {
  let validateUrlResourcesMock: jest.Mock
  let isPending: boolean

  beforeEach(() => {
    jest.clearAllMocks()

    // Setup the mock for useValidateUrlResources hook
    validateUrlResourcesMock = jest.fn()
    isPending = false
    ;(useValidateUrlResources as jest.Mock).mockImplementation(() => ({
      validateUrlResources: validateUrlResourcesMock,
      isPending,
    }))
  })

  test('renders Add via GitHub Url dialog', () => {
    const customCopilot = getCustomCopilotMock({id: 5, oldId: 42})
    const TestWrapper = createTestWrapper(customCopilot)
    render(<TestWrapper />)

    expect(screen.getByRole('heading', {name: 'Add via GitHub URL'})).toBeInTheDocument()
    const textBoxes = screen.getAllByRole('textbox')
    expect(textBoxes.length).toBe(1)
    const addAnotherButton = screen.getByRole('button', {name: 'Add another'})
    expect(addAnotherButton).toBeInTheDocument()

    // no trash button appears when only 1 input is present
    const trashButton = screen.queryByRole('button', {name: 'Remove url'})
    expect(trashButton).not.toBeInTheDocument()
  })

  test('Clicking "Add another" adding additional inputs', async () => {
    const customCopilot = getCustomCopilotMock({id: 5, oldId: 42})
    const TestWrapper = createTestWrapper(customCopilot)
    const {user} = render(<TestWrapper />)

    expect(screen.getByRole('heading', {name: 'Add via GitHub URL'})).toBeInTheDocument()
    const textBoxes = screen.getAllByRole('textbox')
    expect(textBoxes.length).toBe(1)
    const addAnotherButton = screen.getByRole('button', {name: 'Add another'})
    expect(addAnotherButton).toBeInTheDocument()

    await user.click(addAnotherButton)
    expect(screen.getAllByRole('textbox').length).toBe(2)

    await user.click(addAnotherButton)
    expect(screen.getAllByRole('textbox').length).toBe(3)
  })

  test('Clicking the trash icon removes inputs', async () => {
    const customCopilot = getCustomCopilotMock({id: 5, oldId: 42})
    const TestWrapper = createTestWrapper(customCopilot)
    const {user} = render(<TestWrapper />)

    expect(screen.getByRole('heading', {name: 'Add via GitHub URL'})).toBeInTheDocument()
    expect(screen.getAllByRole('textbox').length).toBe(1)
    const addAnotherButton = screen.getByRole('button', {name: 'Add another'})
    expect(addAnotherButton).toBeInTheDocument()

    await user.click(addAnotherButton)
    expect(screen.getAllByRole('textbox').length).toBe(2)

    await user.click(addAnotherButton)
    expect(screen.getAllByRole('textbox').length).toBe(3)

    const trashButtons = screen.getAllByRole('button', {name: 'Remove url'})
    expect(trashButtons.length).toBe(3)

    // remove first input
    await user.click(trashButtons[0] as HTMLButtonElement)
    expect(screen.getAllByRole('textbox').length).toBe(2)
    // remove second input
    await user.click(trashButtons[1] as HTMLButtonElement)
    expect(screen.getAllByRole('textbox').length).toBe(1)

    // no trash button appears when only 1 input is present
    expect(screen.queryByRole('button', {name: 'Remove url'})).not.toBeInTheDocument()
  })

  test('Clicking the trash icon removes the correct input', async () => {
    jest.useFakeTimers()

    const customCopilot = getCustomCopilotMock({id: 5, oldId: 42})
    const TestWrapper = createTestWrapper(customCopilot)
    const {user} = render(<TestWrapper />)

    const addAnotherButton = screen.getByRole('button', {name: 'Add another'})
    expect(addAnotherButton).toBeInTheDocument()

    // add 2 inputs
    await user.click(addAnotherButton)
    await user.click(addAnotherButton)

    const textBoxes = screen.getAllByRole('textbox')
    expect(textBoxes.length).toBe(3)

    await act(async () => {
      // paste text to the first input
      await user.click(textBoxes[0] as HTMLButtonElement)
      await user.paste('hello world')
      // paste text to the second input
      await user.click(textBoxes[1] as HTMLButtonElement)
      await user.paste('hello universe')
      // paste text to the third input
      await user.click(textBoxes[2] as HTMLButtonElement)
      await user.paste('hello galaxy')
      // Trigger debounce
      jest.runAllTimers()
    })

    const trashButtons = screen.getAllByRole('button', {name: 'Remove url'})
    expect(trashButtons.length).toBe(3)

    // remove second input
    const secondTrashButton = trashButtons[1] as HTMLButtonElement
    await user.click(secondTrashButton)
    // sleep for 3 seconds to allow the animation to finish`
    const tb = screen.getAllByRole('textbox')
    expect(tb.length).toBe(2)

    // check that the first input still has the text
    expect(screen.getByDisplayValue('hello world')).toBeInTheDocument()
    // check that the second input is removed
    expect(screen.queryByDisplayValue('hello universe')).not.toBeInTheDocument()
    // check that the third input still has the text
    expect(screen.getByDisplayValue('hello galaxy')).toBeInTheDocument()
  })

  test('Clicking the Add button submits the form', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2025-03-15'))
    const randomUUID = jest.fn().mockName('randomUUID')
    global.crypto.randomUUID = randomUUID
    randomUUID.mockImplementationOnce(() => 'uuid-1').mockImplementationOnce(() => 'uuid-2')

    const customCopilot = getCustomCopilotMock({id: 5, oldId: 42})
    const TestWrapper = createTestWrapper(customCopilot)
    const {user} = render(<TestWrapper />)

    expect(screen.getByRole('heading', {name: 'Add via GitHub URL'})).toBeInTheDocument()
    const addAnotherButton = screen.getByRole('button', {name: 'Add another'})
    expect(addAnotherButton).toBeInTheDocument()

    await user.click(addAnotherButton)
    const textBoxes = screen.getAllByRole('textbox')
    expect(textBoxes.length).toBe(2)

    await act(async () => {
      // paste text to the first input
      await user.click(textBoxes[0] as HTMLButtonElement)
      await user.paste('github.com/github/copilot/pull/3')
      jest.runAllTimers()
    })

    await act(async () => {
      // paste text to the second input
      await user.click(textBoxes[1] as HTMLButtonElement)
      await user.paste('github.com/co/pilot/issues/12')
      // Trigger debounce
      jest.runAllTimers()
    })

    const addButton = screen.getByRole('button', {name: 'Add'})
    expect(addButton).toBeInTheDocument()

    await user.click(addButton)

    expect(validateUrlResourcesMock).toHaveBeenCalledTimes(1)
    await waitFor(() => {
      expect(validateUrlResourcesMock).toHaveBeenCalledWith({
        input: [
          {
            id: 'uuid-1',
            errorMessage: undefined,
            number: 3,
            owner: 'github',
            repo: 'copilot',
            type: 'github_pull_request',
            url: 'github.com/github/copilot/pull/3',
          },
          {
            id: 'uuid-2',
            errorMessage: undefined,
            number: 12,
            owner: 'co',
            repo: 'pilot',
            type: 'github_issue',
            url: 'github.com/co/pilot/issues/12',
          },
        ],
        spaceOwner: undefined,
      })
    })
  })

  test('Displays a validation error if owner is not the same', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2025-03-15'))
    const randomUUID = jest.fn().mockName('randomUUID')
    global.crypto.randomUUID = randomUUID
    randomUUID.mockImplementationOnce(() => 'uuid-1').mockImplementationOnce(() => 'uuid-2')

    const customCopilot = getCustomCopilotMock({id: 5, oldId: 42})
    const TestWrapper = createTestWrapper(customCopilot)
    const {user} = render(<TestWrapper owner="monalisa" />)

    expect(screen.getByRole('heading', {name: 'Add via GitHub URL'})).toBeInTheDocument()

    const textBoxes = screen.getAllByRole('textbox')
    await act(async () => {
      // paste text to the first input
      await user.click(textBoxes[0] as HTMLButtonElement)
      await user.paste('github.com/co/copilot/pull/3')
      jest.runAllTimers()
    })

    const addButton = screen.getByRole('button', {name: 'Add'})
    expect(addButton).toBeInTheDocument()

    await user.click(addButton)

    expect(validateUrlResourcesMock).toHaveBeenCalledTimes(0)
    expect(screen.getByText("This doesn't belong to the monalisa organization.")).toBeInTheDocument()
  })
})
