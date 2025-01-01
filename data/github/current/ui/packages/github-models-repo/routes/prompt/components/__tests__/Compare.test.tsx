import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {PromptCompareManagerContext, type PromptCompareManager} from '../../prompt-compare-manager'
import type {RepoModel} from '../../../../types'
import type {EvalsRow, PromptAppPayload} from '../../types'
import {
  getPromptAppPayload,
  mockModel,
  mockPromptCompareState,
  mockPromptConfig,
} from '../../../../test-utils/mock-data'
import {Compare} from '../Compare'
import {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import type {PromptCompareState} from '../../prompt-compare-state'
import {PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'

const playgroundUrl = 'azure-ai-playground-url.com'
const mockModelClient = new AzureModelClient(playgroundUrl)
const setError = jest.fn().mockName('setError')
const startEvalsRun = jest.fn().mockName('startEvalsRun')
const evalsAddRow = jest.fn().mockName('evalsAddRow')
const evalsRemoveRow = jest.fn().mockName('evalsRemoveRow')
const addPrompt = jest.fn().mockName('addPrompt')
const removePrompt = jest.fn().mockName('removePrompt')
const evalsAddOrUpdateRow = jest.fn().mockName('evalsAddOrUpdateRow')
const evalsToggleRowSkip = jest.fn().mockName('evalsToggleRowSkip')

const manager = {} as PromptCompareManager
manager.setError = setError
manager.startEvalsRun = startEvalsRun
manager.evalsAddRow = evalsAddRow
manager.evalsRemoveRow = evalsRemoveRow
manager.addPrompt = addPrompt
manager.removePrompt = removePrompt
manager.evalsAddOrUpdateRow = evalsAddOrUpdateRow
manager.evalsToggleRowSkip = evalsToggleRowSkip

// Mock the models loading
const mockUseModels = jest.fn().mockName('mockUseModels').mockReturnValue([])
jest.mock('../../contexts/ModelsContext', () => ({
  useModels: () => mockUseModels(),
}))

describe('Compare', () => {
  it('can add a new row if the number of rows is less than 100', async () => {
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`

    const {user} = render(<Compare mode="compare" modelClient={mockModelClient} />, {appPayload, pathname})

    const addInputs = screen.getByRole('button', {name: 'Add input'})
    expect(addInputs).not.toHaveAttribute('disabed')

    await user.click(addInputs)

    const addRowDialog = screen.getByRole('dialog', {name: 'Add Row'})
    expect(addRowDialog).toBeInTheDocument()
    const dialogSubmitButton = within(addRowDialog).getByRole('button', {name: 'Add'})
    expect(dialogSubmitButton).toBeInTheDocument()
    expect(dialogSubmitButton).toBeEnabled()
    const input = within(addRowDialog).getByRole('textbox', {name: 'input'})
    expect(input).toBeInTheDocument()

    await user.type(input, 'cats')

    expect(evalsAddRow).not.toHaveBeenCalled()

    await user.click(dialogSubmitButton)

    expect(evalsAddRow).toHaveBeenCalledTimes(1)
    expect(evalsAddRow).toHaveBeenCalledWith({input: 'cats'})
    expect(screen.queryByRole('dialog', {name: 'Add Row'})).not.toBeInTheDocument()
  })

  it('cannot add a new row if the number of rows is more than or equal to 100', async () => {
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`

    const promptCompareState = mockPromptCompareState({
      compare: {
        isRunning: false,
        rows: Array.from({length: 100}, (_, i) => ({id: `${i}`})),
        result: {},
        evaluators: [],
      },
    })

    render(<Compare mode="compare" modelClient={mockModelClient} />, {appPayload, pathname}, promptCompareState)

    const addInputs = screen.getByRole('button', {name: 'Add input'})
    expect(addInputs).toHaveAttribute('disabled')
  })

  it('allows removing a row', async () => {
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
    const row: EvalsRow = {input: 'cats', id: '123'}
    const prompt = mockPromptConfig({
      messages: [{role: 'system', message: 'You explain concepts', timestamp: new Date()}],
    })
    const promptCompareState = mockPromptCompareState({prompts: [prompt], compare: {rows: [row]}})

    const {user} = render(
      <Compare mode="compare" modelClient={mockModelClient} />,
      {appPayload, pathname},
      promptCompareState,
    )

    const editRowButton = screen.getByRole('button', {name: 'Edit row 123'})
    expect(editRowButton).toBeInTheDocument()
    expect(editRowButton).toBeEnabled()
    expect(screen.queryByRole('dialog', {name: 'Edit Row'})).not.toBeInTheDocument()

    await user.click(editRowButton)

    const dialog = screen.getByRole('dialog', {name: 'Edit Row'})
    expect(dialog).toBeInTheDocument()
    const deleteButton = within(dialog).getByRole('button', {name: 'Delete row'})
    expect(deleteButton).toBeInTheDocument()
    expect(deleteButton).toBeEnabled()

    await user.click(deleteButton)

    expect(evalsRemoveRow).toHaveBeenCalledTimes(1)
    expect(evalsRemoveRow).toHaveBeenCalledWith('123')
    expect(screen.queryByRole('dialog', {name: 'Edit Row'})).not.toBeInTheDocument()
  })

  it('allows skipping a row', async () => {
    evalsToggleRowSkip.mockReset()
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
    const row: EvalsRow = {input: 'cats', id: '123'}
    const prompt = mockPromptConfig({
      messages: [{role: 'user', message: 'You explain concepts', timestamp: new Date()}],
    })
    const promptCompareState = mockPromptCompareState({prompts: [prompt], compare: {rows: [row]}})

    const {user} = render(
      <Compare mode="compare" modelClient={mockModelClient} />,
      {appPayload, pathname},
      promptCompareState,
    )

    const skipButton = screen.getByRole('button', {name: 'Skip row 123'})
    expect(skipButton).toBeInTheDocument()
    expect(skipButton).toBeEnabled()
    expect(screen.queryByRole('button', {name: 'Unskip row 123'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Run'})).toBeEnabled()
    expect(screen.getByRole('button', {name: 'Run'})).not.toHaveAttribute('data-inactive')
    expect(evalsToggleRowSkip).not.toHaveBeenCalled()

    await user.click(skipButton)

    expect(evalsToggleRowSkip).toHaveBeenCalledTimes(1)
    expect(evalsToggleRowSkip).toHaveBeenCalledWith('123')
  })

  it('allows unskipping a row', async () => {
    evalsToggleRowSkip.mockReset()
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
    const row: EvalsRow = {input: 'cats', id: '123'}
    const prompt = mockPromptConfig({
      messages: [{role: 'user', message: 'You explain concepts', timestamp: new Date()}],
    })
    const promptCompareState = mockPromptCompareState({
      prompts: [prompt],
      compare: {rows: [row], skippedRowIds: new Set(['123'])},
    })

    const {user} = render(
      <Compare mode="compare" modelClient={mockModelClient} />,
      {appPayload, pathname},
      promptCompareState,
    )

    const unskipButton = screen.getByRole('button', {name: 'Unskip row 123'})
    expect(unskipButton).toBeInTheDocument()
    expect(unskipButton).toBeEnabled()
    expect(screen.queryByRole('button', {name: 'Skip row 123'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Run'})).toBeEnabled()
    expect(screen.getByRole('button', {name: 'Run'})).toHaveAttribute('data-inactive', 'true')
    expect(evalsToggleRowSkip).not.toHaveBeenCalled()

    await user.click(unskipButton)

    expect(evalsToggleRowSkip).toHaveBeenCalledTimes(1)
    expect(evalsToggleRowSkip).toHaveBeenCalledWith('123')
  })

  describe('Run button', () => {
    it('logs a click event when the user clicks run', async () => {
      const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
      const repo = appPayload.payload.repository
      const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
      const modified_prompt = mockPromptConfig({
        messages: [{role: 'user', message: 'Why is the sky blue?', timestamp: new Date()}],
      })
      const promptCompareState = mockPromptCompareState({
        prompts: [modified_prompt],
        compare: {
          isRunning: false,
          rows: Array.from({length: 10}, (_, i) => ({id: `${i}`})),
          result: {},
          evaluators: [],
        },
      })

      const {user} = render(
        <Compare mode="compare" modelClient={mockModelClient} />,
        {appPayload, pathname},
        promptCompareState,
      )
      const button = screen.getByRole('button', {name: 'Run'})
      await user.click(button)

      expectAnalyticsEvents({
        type: 'analytics.click',
        data: {
          category: 'github_models_repo_integration',
          action: 'click_compare_run',
        },
      })
    })

    it('renders inactive button with message to add rows to run', () => {
      const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
      const repo = appPayload.payload.repository
      const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
      const modified_prompt = mockPromptConfig({
        messages: [{role: 'user', message: 'Why is the sky blue?', timestamp: new Date()}],
      })
      const promptCompareState = mockPromptCompareState({
        prompts: [modified_prompt],
        compare: {
          isRunning: false,
          rows: [],
          result: {},
          evaluators: [],
        },
      })

      render(<Compare mode="compare" modelClient={mockModelClient} />, {appPayload, pathname}, promptCompareState)

      const button = screen.getByRole('button', {name: 'Run'})
      expect(button).toHaveAttribute('data-inactive')
      expect(screen.getByText('Add rows to run')).toBeInTheDocument()
    })

    it('renders inactive button with message to select a model for each prompt to run', () => {
      const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
      const repo = appPayload.payload.repository
      const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
      const modified_prompt = mockPromptConfig({
        messages: [{role: 'user', message: 'Why is the sky blue?', timestamp: new Date()}],
        model: '',
      })
      const promptCompareState = mockPromptCompareState({
        prompts: [modified_prompt],
        compare: {
          isRunning: false,
          rows: Array.from({length: 10}, (_, i) => ({id: `${i}`})),
          result: {},
          evaluators: [],
        },
      })

      render(<Compare mode="compare" modelClient={mockModelClient} />, {appPayload, pathname}, promptCompareState)

      const button = screen.getByRole('button', {name: 'Run'})
      expect(button).toHaveAttribute('data-inactive')
      expect(screen.getByText('Select a model for each prompt to run')).toBeInTheDocument()
    })

    it('renders inactive button with message that every prompt needs a user prompt', () => {
      const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
      const repo = appPayload.payload.repository
      const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
      const modified_prompt = mockPromptConfig({
        messages: [{role: 'assistant', message: 'You are an assistant', timestamp: new Date()}],
      })
      const promptCompareState = mockPromptCompareState({
        prompts: [modified_prompt],
        compare: {
          isRunning: false,
          rows: Array.from({length: 10}, (_, i) => ({id: `${i}`})),
          result: {},
          evaluators: [],
        },
      })

      render(<Compare mode="compare" modelClient={mockModelClient} />, {appPayload, pathname}, promptCompareState)

      const button = screen.getByRole('button', {name: 'Run'})
      expect(button).toHaveAttribute('data-inactive')
      expect(screen.getByText('Every prompt needs a user prompt to run')).toBeInTheDocument()
    })
  })

  describe('Sample', () => {
    it('renders the loading sample spinner when the models are loading', () => {
      const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
      const repo = appPayload.payload.repository
      const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/compare/main?sample`

      render(<Compare mode="compare" modelClient={mockModelClient} isNewPrompt />, {
        appPayload,
        pathname,
        search: '?sample',
      })

      expect(screen.getByText('Loading sample data...')).toBeInTheDocument()
    })

    it('renders the same data when the url has the `sample` query param', async () => {
      const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
      const repo = appPayload.payload.repository
      const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/compare/main?sample`

      mockUseModels.mockReturnValue([
        mockModel({id: 'model1', name: 'Model 1'}),
        mockModel({id: 'model2', name: 'Model 2'}),
        mockModel({id: 'model3', name: 'Model 3'}),
      ] satisfies RepoModel[])

      render(<Compare mode="compare" modelClient={mockModelClient} isNewPrompt />, {
        appPayload,
        pathname,
        search: '?sample',
      })

      expect(mockUseModels).toHaveBeenCalled()
      expect(removePrompt).toHaveBeenCalledTimes(1)
      expect(addPrompt).toHaveBeenCalledTimes(3)
      expect(evalsAddOrUpdateRow).toHaveBeenCalledTimes(2)
    })
  })

  it('displays dynamic columns based on variables in prompt', async () => {
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`
    const row: EvalsRow = {input: 'cats', subject: 'animals', context: 'pets', id: '123'}
    const prompt = mockPromptConfig({
      messages: [
        {
          role: 'user',
          message: 'Tell me about {{subject}} in the context of {{context}} using this input: {{input}}',
          timestamp: new Date(),
        },
      ],
    })
    const promptCompareState = mockPromptCompareState({prompts: [prompt], compare: {rows: [row]}})

    render(<Compare mode="compare" modelClient={mockModelClient} />, {appPayload, pathname}, promptCompareState)

    // Check that the table has a consolidated Input column with all variables displayed within it
    expect(screen.getByRole('columnheader', {name: 'Input'})).toBeInTheDocument()
    expect(screen.getByRole('columnheader', {name: 'Output 1'})).toBeInTheDocument()

    // Check that all variable values are displayed in the consolidated Input column
    expect(screen.getByText('animals')).toBeInTheDocument()
    expect(screen.getByText('pets')).toBeInTheDocument()
    expect(screen.getByText('cats')).toBeInTheDocument()
  })
})

function render(component: JSX.Element, opts: TestRenderOptions = {}, promptCompareState?: PromptCompareState) {
  let repository
  if (opts.appPayload) {
    const {payload} = opts.appPayload as PromptAppPayload
    repository = payload.repository
  }
  repository = repository || createRepository()

  return htmlRender(
    <CurrentRepositoryProvider repository={repository}>
      <PromptCompareStateProvider state={promptCompareState ?? mockPromptCompareState()}>
        <PromptCompareManagerContext.Provider value={manager}>{component}</PromptCompareManagerContext.Provider>
      </PromptCompareStateProvider>
    </CurrentRepositoryProvider>,
    opts,
  )
}
