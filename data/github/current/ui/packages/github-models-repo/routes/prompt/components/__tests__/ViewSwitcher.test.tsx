import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ViewSwitcher} from '../ViewSwitcher'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {repoModelsPromptPath, repoPromptNewPath} from '@github-ui/paths'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import type {PromptAppPayload} from '../../types'
import {PromptCompareManagerContext, type PromptCompareManager} from '../../prompt-compare-manager'
import {getPromptAppPayload} from '../../../../test-utils/mock-data'

const appPayload = getPromptAppPayload({payload: {promptPath: ''}})
const repo = appPayload.payload.repository

const updatePromptPath = jest.fn().mockName('updatePromptPath')
const mockNavigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigateFn,
  }
})

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: () => ({owner: repo.ownerLogin, repo: repo.name}),
}))

describe('ViewSwitcher', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders correctly with prompt view selected by default', () => {
    render(<ViewSwitcher />)

    const promptButton = screen.getByRole('button', {name: 'Edit'})
    const compareButton = screen.getByRole('button', {name: 'Compare'})
    expect(promptButton).toBeInTheDocument()
    expect(compareButton).toBeInTheDocument()

    expect(promptButton).toHaveAttribute('aria-current', 'true')
    expect(compareButton).toHaveAttribute('aria-current', 'false')
  })

  it('renders with compare view selected when URL includes compare', () => {
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/compare`

    render(<ViewSwitcher />, {appPayload, pathname})

    const promptButton = screen.getByRole('button', {name: 'Edit'})
    const compareButton = screen.getByRole('button', {name: 'Compare'})

    expect(promptButton).toHaveAttribute('aria-current', 'false')
    expect(compareButton).toHaveAttribute('aria-current', 'true')
  })

  it('navigates to compare view when Compare button is clicked', async () => {
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`

    const {user} = render(<ViewSwitcher />, {appPayload, pathname})

    const compareButton = screen.getByRole('button', {name: 'Compare'})
    await user.click(compareButton)

    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: repoModelsPromptPath({
        repo,
        commitish: repo.defaultBranch,
        action: 'compare',
      }),
    })
  })

  it('navigates to prompt view when Prompt button is clicked from compare view', async () => {
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/compare/main/fun-prompts/teacher.prompt.yml`

    const {user} = render(<ViewSwitcher />, {appPayload, pathname})

    const promptButton = screen.getByRole('button', {name: 'Edit'})
    await user.click(promptButton)

    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: repoModelsPromptPath({
        repo,
        commitish: repo.defaultBranch,
        action: 'edit',
      }),
    })
  })

  it('navigates to new prompt view when Prompt button is clicked from compare view for a new prompt', async () => {
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/compare/main`

    const {user} = render(<ViewSwitcher />, {appPayload, pathname})

    const promptButton = screen.getByRole('button', {name: 'Edit'})
    await user.click(promptButton)

    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: repoPromptNewPath(repo),
    })
  })

  it('uses repo default branch when branch param is not provided', async () => {
    const pathname = `/${repo.ownerLogin}/${repo.name}/models/prompt/new`

    const {user} = render(<ViewSwitcher />, {appPayload, pathname})

    const compareButton = screen.getByRole('button', {name: 'Compare'})
    await user.click(compareButton)

    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: repoModelsPromptPath({
        repo,
        commitish: repo.defaultBranch,
        action: 'compare',
      }),
    })
  })

  it('does not navigate when disabled prop is true', async () => {
    const {user} = render(<ViewSwitcher disabled />)

    const compareButton = screen.getByRole('button', {name: 'Compare'})
    await user.click(compareButton)

    expect(mockNavigateFn).not.toHaveBeenCalled()
  })

  it('does not navigate when clicking on already selected view', async () => {
    render(<ViewSwitcher />)

    const promptButton = screen.getByRole('button', {name: 'Edit'})
    await promptButton.click()

    expect(mockNavigateFn).not.toHaveBeenCalled()
  })

  it('disables buttons when disabled prop is true', () => {
    render(<ViewSwitcher disabled />)

    const promptButton = screen.getByRole('button', {name: 'Edit'})
    const compareButton = screen.getByRole('button', {name: 'Compare'})

    expect(promptButton).toHaveAttribute('disabled')
    expect(compareButton).toHaveAttribute('disabled')
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
})
