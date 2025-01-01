import {screen} from '@testing-library/react'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {mockModelListing} from '@github-ui/marketplace-common/mock-data'
import {renderWithFilterContext} from '@github-ui/marketplace-common/test-utils'
import {ResultListHeader, modelsFeedbackUrl} from '../ResultListHeader'
import {mockResizeObserver} from '../../routes/playground/components/GettingStartedDialog/__tests__/mocks'

jest.mock('@github-ui/feature-flags')
jest.mock('@github-ui/use-navigate')

const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

const recentModels = [
  mockModelListing({id: '1', friendly_name: 'Recent Model A'}),
  mockModelListing({id: '2', friendly_name: 'Recent Model B'}),
  mockModelListing({id: '3', friendly_name: 'Recent Model C'}),
]

const popularModels = [
  mockModelListing({id: '4', friendly_name: 'Popular Model A'}),
  mockModelListing({id: '5', friendly_name: 'Popular Model B'}),
  mockModelListing({id: '6', friendly_name: 'Popular Model C'}),
]

describe('ResultListHeader', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()

    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    useSearchParams.mockImplementation(() => [new URLSearchParams(), jest.fn()])
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders search heading when searching', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('query', 'something sort:created-desc')
    params.set('type', 'models')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderWithFilterContext(<ResultListHeader />)

    expect(screen.getByRole('heading', {level: 2, name: 'Search results for “something”'})).toBeInTheDocument()
    expect(screen.getByTestId('detail-text')).toHaveTextContent('10 results')
  })

  test('renders models heading when not searching', () => {
    const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
    const params = new URLSearchParams()
    params.set('type', 'models')
    useSearchParams.mockImplementation(() => [params, jest.fn()])
    renderWithFilterContext(<ResultListHeader />)

    expect(screen.getByRole('heading', {level: 2, name: 'Models'})).toBeInTheDocument()
    expect(screen.getByTestId('detail-text')).toHaveTextContent(
      'Create applications with GitHub powered by AI Models. Free to use, quick personal setup, and seamless model switching to help you build AI products using the latest models.',
    )
  })

  test('renders with lifecycle label when feature is enabled', () => {
    mockIsFeatureEnabled.mockReturnValue(true)

    renderWithFilterContext(<ResultListHeader />)

    expect(screen.getByTestId('heading-text')).toHaveTextContent('Models')
    expect(screen.getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', modelsFeedbackUrl)
    expect(screen.getByText('Preview')).toBeInTheDocument()
  })

  test('renders with default beta label when lifecycle label feature is disabled', () => {
    mockIsFeatureEnabled.mockReturnValue(false)

    renderWithFilterContext(<ResultListHeader />)

    expect(screen.getByText('Beta')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', modelsFeedbackUrl)
  })

  test('renders recently added models by default', () => {
    renderWithFilterContext(<ResultListHeader />, {recentModels, popularModels})

    expect(screen.getByTestId('detail-text')).toHaveTextContent(
      'Create applications with GitHub powered by AI Models. Free to use, quick personal setup, and seamless model switching to help you build AI products using the latest models.',
    )
    expect(screen.getByRole('link', {name: 'Try models in playground'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Recently added'})).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('button', {name: 'Most popular'})).not.toHaveAttribute('aria-current', 'page')

    expect(screen.getByText('Recent Model A')).toBeInTheDocument()
    expect(screen.getByText('Recent Model B')).toBeInTheDocument()
    expect(screen.getByText('Recent Model C')).toBeInTheDocument()

    expect(screen.queryByText('Popular Model A')).not.toBeInTheDocument()
    expect(screen.queryByText('Popular Model B')).not.toBeInTheDocument()
    expect(screen.queryByText('Popular Model C')).not.toBeInTheDocument()
  })

  test('renders most popular models when selected', async () => {
    const {user} = renderWithFilterContext(<ResultListHeader />, {recentModels, popularModels})

    expect(screen.getByRole('link', {name: 'Try models in playground'})).toBeInTheDocument()
    const popularTab = screen.getByRole('button', {name: 'Most popular'})
    await user.click(popularTab)

    expect(screen.getByRole('button', {name: 'Recently added'})).not.toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('button', {name: 'Most popular'})).toHaveAttribute('aria-current', 'page')

    expect(screen.getByText('Popular Model A')).toBeInTheDocument()
    expect(screen.getByText('Popular Model B')).toBeInTheDocument()
    expect(screen.getByText('Popular Model C')).toBeInTheDocument()

    expect(screen.queryByText('Recent Model A')).not.toBeInTheDocument()
    expect(screen.queryByText('Recent Model B')).not.toBeInTheDocument()
    expect(screen.queryByText('Recent Model C')).not.toBeInTheDocument()
  })
})
