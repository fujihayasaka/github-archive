import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {screen} from '@testing-library/react'
import type {PromptConfig} from '../../prompts'
import {PromptCompareManagerContext, type PromptCompareManager} from '../../prompt-compare-manager'
import {PromptFileHeader} from '../PromptFileHeader'
import type {PromptAppPayload} from '../../types'
import {getPromptAppPayload} from '../../../../test-utils/mock-data'

const setDialogState = jest.fn().mockName('setDialogState')
const updatePromptPath = jest.fn().mockName('updatePromptPath')

describe('PromptFileHeader', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders file name field for new prompt on new-prompt page', () => {
    const prompt: PromptConfig = {messages: []}
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`

    render(<PromptFileHeader setDialogState={setDialogState} isDirty prompt={prompt} />, {appPayload, pathname})

    const fileNameInput = screen.getByRole('textbox', {name: 'File name'})
    expect(fileNameInput).toBeInTheDocument()
    expect(fileNameInput).toBeEnabled()
    expect(fileNameInput).toHaveValue('')
    expect(updatePromptPath).not.toHaveBeenCalled()
    expect(setDialogState).not.toHaveBeenCalled()
  })

  it('renders file name field for new prompt on compare page', async () => {
    const newFileName = 'foo'
    const prompt: PromptConfig = {path: `${newFileName}.prompt.yml`, messages: []}
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/compare/${repo.defaultBranch}`

    const {user} = render(<PromptFileHeader setDialogState={setDialogState} isDirty prompt={prompt} />, {
      appPayload,
      pathname,
    })

    const fileNameInput = screen.getByRole('textbox', {name: 'File name'})
    expect(fileNameInput).toBeInTheDocument()
    expect(fileNameInput).toBeEnabled()
    expect(fileNameInput).toHaveValue('')
    expect(updatePromptPath).not.toHaveBeenCalled()

    await user.type(fileNameInput, newFileName)

    expect(fileNameInput).toBeEnabled()
    expect(fileNameInput).toHaveValue(newFileName)
    expect(updatePromptPath).toHaveBeenCalledWith(`${newFileName}.prompt.yml`)
    expect(setDialogState).not.toHaveBeenCalled()
  })

  it('renders without setDialogState', async () => {
    const prompt: PromptConfig = {messages: []}
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`

    const {user} = render(<PromptFileHeader isDirty prompt={prompt} />, {appPayload, pathname})

    const fileNameInput = screen.getByRole('textbox', {name: 'File name'})
    expect(fileNameInput).toBeInTheDocument()
    expect(fileNameInput).toBeEnabled()
    expect(fileNameInput).toHaveValue('')

    const commitButton = screen.getByRole('button', {name: 'Commit changes'})
    expect(commitButton).toBeInTheDocument()
    await user.click(commitButton)
    expect(setDialogState).not.toHaveBeenCalled()
  })

  it('renders with commit button inactive', () => {
    const prompt: PromptConfig = {messages: []}
    const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
    const repo = appPayload.payload.repository
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`

    render(<PromptFileHeader setDialogState={setDialogState} isDirty={false} prompt={prompt} />, {
      appPayload,
      pathname,
    })

    const fileNameInput = screen.getByRole('textbox', {name: 'File name'})
    expect(fileNameInput).toBeInTheDocument()
    expect(fileNameInput).toBeEnabled()
    expect(fileNameInput).toHaveValue('')

    const commitButton = screen.getByRole('button', {name: 'Commit changes'})
    expect(commitButton).toBeInTheDocument()
    expect(commitButton).toHaveAttribute('data-inactive')
  })
})

function render(component: JSX.Element, opts: TestRenderOptions = {}) {
  let repository
  if (opts.appPayload) {
    const {payload} = opts.appPayload as PromptAppPayload
    repository = payload.repository
  }
  repository = repository || createRepository()

  const manager = {} as PromptCompareManager
  manager.updatePromptPath = updatePromptPath

  return htmlRender(
    <CurrentRepositoryProvider repository={repository}>
      <PromptCompareManagerContext.Provider value={manager}>{component}</PromptCompareManagerContext.Provider>
    </CurrentRepositoryProvider>,
    opts,
  )
}
