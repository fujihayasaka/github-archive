import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {
  getPromptAppPayload,
  mockCommitInfo,
  mockPromptConfig,
  mockResizeObserver,
  mockWebCommitInfo,
} from '../../../../test-utils/mock-data'
import PromptWebCommitDialog from '../PromptWebCommitDialog'

const setDialogState = jest.fn().mockName('setDialogState')
const mockVerifiedFetch = jest.fn().mockName('verifiedFetch')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetch: (...args: unknown[]) => mockVerifiedFetch(...args),
  }
})

describe('PromptWebCommitDialog', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders for an existing prompt', async () => {
    const prompt = mockPromptConfig({path: 'path/to/my/foo.prompt.yml'})
    const appPayload = getPromptAppPayload()

    const {user} = render(
      <PromptWebCommitDialog dialogState="pending" setDialogState={setDialogState} activePrompt={prompt} />,
      {
        appPayload,
      },
    )

    const dialog = await screen.findByRole('dialog', {name: 'Commit changes'}, {timeout: 2000})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Commit changes'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Commit changes'})).toBeInTheDocument()
    const commitMessageInput = within(dialog).getByRole('textbox', {name: 'Commit message'})
    expect(commitMessageInput).toBeInTheDocument()
    expect(commitMessageInput).toHaveValue('Update foo.prompt.yml')
    expect(setDialogState).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(setDialogState).toHaveBeenCalledTimes(1)
    expect(setDialogState).toHaveBeenCalledWith('closed')
    expect(mockVerifiedFetch).not.toHaveBeenCalled()
  })

  it('renders for a new prompt', async () => {
    const prompt = mockPromptConfig({name: 'My Favorite Prompt'})
    const pathname = '/monalisa/models-stuff/models/prompt/new'
    const saveUrl = '/monalisa/models-stuff/make-a-commit'
    const commitInfo = Object.assign({}, mockCommitInfo, {
      webCommitInfo: Object.assign({}, mockWebCommitInfo, {
        saveUrl,
      }),
    })
    const appPayload = getPromptAppPayload({payload: {commitInfo}})

    const {user} = render(
      <PromptWebCommitDialog dialogState="pending" setDialogState={setDialogState} activePrompt={prompt} />,
      {
        appPayload,
        pathname,
      },
    )

    const dialog = await screen.findByRole('dialog', {name: 'Commit changes'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Commit changes'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const commitButton = within(dialog).getByRole('button', {name: 'Commit changes'})
    expect(commitButton).toBeInTheDocument()
    const commitMessageInput = within(dialog).getByRole('textbox', {name: 'Commit message'})
    expect(commitMessageInput).toBeInTheDocument()
    expect(commitMessageInput).toHaveValue('Create My Favorite Prompt')
    expect(setDialogState).not.toHaveBeenCalled()
    expect(mockVerifiedFetch).not.toHaveBeenCalled()

    await user.click(commitButton)

    expect(setDialogState).toHaveBeenCalled()
    expect(setDialogState).toHaveBeenCalledWith('saving')
    expect(mockVerifiedFetch).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetch).toHaveBeenCalledWith(saveUrl, {
      body: expect.any(FormData),
      headers: {Accept: 'application/json'},
      method: 'post',
    })
  })
})
