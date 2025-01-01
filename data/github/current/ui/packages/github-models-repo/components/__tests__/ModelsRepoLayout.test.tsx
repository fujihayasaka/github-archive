import {render} from '@github-ui/react-core/test-utils'
import {ModelsRepoLayout} from '../ModelsRepoLayout'
import {screen} from '@testing-library/react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useLocation} from 'react-router-dom'

jest.mock('@github-ui/react-core/use-app-payload')
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useLocation: jest.fn(),
}))

const mockedUseAppPayload = jest.mocked(useAppPayload)
const mockedUseLocation = jest.mocked(useLocation)

describe('ModelsRepoLayout', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    mockedUseLocation.mockReturnValue({
      pathname: '/models/playground',
      search: '',
      hash: '',
      state: null,
      key: 'default',
    })
  })

  test('renders Playground tab if the user has the playground feature flag and can edit', () => {
    mockedUseAppPayload.mockReturnValue({
      repository: {name: 'test', ownerLogin: 'user'},
      canEdit: true,
      enabled_features: {github_models_repo_playground: true},
    })
    render(<ModelsRepoLayout fileTreeExpanded setFileTreeExpanded={() => {}} />)

    expect(screen.getByRole('link', {name: 'Playground'})).toBeInTheDocument()
  })

  test('does not render Playground tab if the user does not have the playground feature flag', () => {
    mockedUseAppPayload.mockReturnValue({
      repository: {name: 'test', ownerLogin: 'user'},
      canEdit: true,
      enabled_features: {github_models_repo_playground: false},
    })
    render(<ModelsRepoLayout fileTreeExpanded setFileTreeExpanded={() => {}} />)

    expect(screen.queryByRole('link', {name: 'Playground'})).not.toBeInTheDocument()
  })

  test('does not render Playground tab if the user cannot edit the repository', () => {
    mockedUseAppPayload.mockReturnValue({
      repository: {name: 'test', ownerLogin: 'user'},
      canEdit: false,
      enabled_features: {github_models_repo_playground: true},
    })
    render(<ModelsRepoLayout fileTreeExpanded setFileTreeExpanded={() => {}} />)

    expect(screen.queryByRole('link', {name: 'Playground'})).not.toBeInTheDocument()
  })

  test('highlights Playground tab as current when on models/:publisher/:modelName/playground path', () => {
    mockedUseAppPayload.mockReturnValue({
      repository: {name: 'test', ownerLogin: 'user'},
      canEdit: true,
      enabled_features: {github_models_repo_playground: true},
    })

    mockedUseLocation.mockReturnValue({
      pathname: '/user/test/models/openai/gpt-4/playground',
      search: '',
      hash: '',
      state: null,
      key: 'default',
    })

    render(<ModelsRepoLayout fileTreeExpanded setFileTreeExpanded={() => {}} />)

    const playgroundLink = screen.getByRole('link', {name: 'Playground'})
    expect(playgroundLink).toHaveAttribute('aria-current', 'page')
  })

  test('does not render Comparisons tab if the user does not have the Comparisons feature flag', () => {
    mockedUseAppPayload.mockReturnValue({
      repository: {name: 'test', ownerLogin: 'user'},
      canEdit: true,
      enabled_features: {github_models_repo_comparisons: false},
    })
    render(<ModelsRepoLayout fileTreeExpanded setFileTreeExpanded={() => {}} />)

    expect(screen.queryByRole('link', {name: 'Comparisons'})).not.toBeInTheDocument()
  })

  test('renders Comparisons tab if the user has the Comparisons feature flag', () => {
    mockedUseAppPayload.mockReturnValue({
      repository: {name: 'test', ownerLogin: 'user'},
      canEdit: true,
      enabled_features: {github_models_repo_comparisons: true},
    })
    render(<ModelsRepoLayout fileTreeExpanded setFileTreeExpanded={() => {}} />)

    expect(screen.getByRole('link', {name: 'Comparisons'})).toBeInTheDocument()
  })
})
