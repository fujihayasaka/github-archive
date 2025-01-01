import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ModelsPlaygroundRoute} from '../ModelsPlaygroundRoute'
import {mockModel, mockGettingStartedPayload} from './mocks'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {PlaygroundContentOption, playgroundContentSuffixes} from '../components/types'

jest.mock('@github-ui/react-core/use-route-payload')
jest.mock('@github-ui/react-core/use-feature-flag')

const mockNavigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigateFn,
    useSearchParams: () => [new URLSearchParams(), () => jest.fn()],
  }
})

window.performance.mark = jest.fn()
window.performance.measure = jest.fn()
window.performance.clearResourceTimings = jest.fn()
window.performance.getEntriesByName = jest.fn().mockReturnValue([{duration: 100}])

const mockUseRoutePayload = jest.mocked(useRoutePayload)
const mockUseFeatureFlags = jest.mocked(useFeatureFlags)
mockUseFeatureFlags.mockReturnValue({
  project_neutron_rag: false,
})

describe('ModelsPlaygroundRoute', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders the playground', async () => {
    const mockRoutePayload = mockGettingStartedPayload({model: mockModel})
    mockUseRoutePayload.mockReturnValue(mockRoutePayload)

    const {container} = render(<ModelsPlaygroundRoute />)

    expect(within(container).queryByTestId('waitlist-message')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('join-waitlist-button')).not.toBeInTheDocument()
    const playgroundContainer = within(container).getByTestId('playground')
    expect(playgroundContainer).toBeInTheDocument()
    expect(within(playgroundContainer).getByTestId('model-friendly-name')).toHaveTextContent(mockModel.friendly_name)
    expect(within(playgroundContainer).getByTestId('feedback-link')).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('textbox', {name: 'Prompt'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Get API key'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Chat'})).toHaveAttribute('aria-current', 'true')
    expect(within(playgroundContainer).getByRole('button', {name: 'Code'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Raw'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Reset chat history'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Show model info'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Show parameters setting'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('heading', {name: mockModel.friendly_name})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('paragraph')).toHaveTextContent(mockModel.summary || '')
    expect(within(playgroundContainer).getByRole('button', {name: 'Send now'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('button', {name: 'Share feedback'})).toBeInTheDocument()
    expect(within(playgroundContainer).getByTestId('legal-terms')).toBeInTheDocument()
    expect(within(playgroundContainer).getByRole('list', {name: 'Show playground chat'})).toBeInTheDocument()
  })

  test('allows switching to Code tab', async () => {
    const mockRoutePayload = mockGettingStartedPayload({
      model: mockModel,
      playgroundUrl: ModelUrlHelper.playgroundUrl(mockModel),
    })
    mockUseRoutePayload.mockReturnValue(mockRoutePayload)

    const {container, user} = render(<ModelsPlaygroundRoute />)

    const playgroundContainer = within(container).getByTestId('playground')
    const codeButton = within(playgroundContainer).getByRole('button', {name: 'Code'})
    expect(codeButton).not.toHaveAttribute('aria-current', 'true')

    await user.click(codeButton)

    expect(codeButton).toHaveAttribute('aria-current', 'true')
    const suffix = playgroundContentSuffixes[PlaygroundContentOption.CODE]
    const playgroundCodeUrl = `${ModelUrlHelper.playgroundUrl(mockModel)}${suffix}`
    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: playgroundCodeUrl,
      search: '',
    })
  })

  test('allows switching to Raw tab', async () => {
    const mockRoutePayload = mockGettingStartedPayload({
      model: mockModel,
      playgroundUrl: ModelUrlHelper.playgroundUrl(mockModel),
    })
    mockUseRoutePayload.mockReturnValue(mockRoutePayload)

    const {container, user} = render(<ModelsPlaygroundRoute />)

    const playgroundContainer = within(container).getByTestId('playground')
    const codeButton = within(playgroundContainer).getByRole('button', {name: 'Raw'})
    expect(codeButton).not.toHaveAttribute('aria-current', 'true')

    await user.click(codeButton)

    expect(codeButton).toHaveAttribute('aria-current', 'true')
    const suffix = playgroundContentSuffixes[PlaygroundContentOption.JSON]
    const playgroundJsonUrl = `${ModelUrlHelper.playgroundUrl(mockModel)}${suffix}`
    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: playgroundJsonUrl,
      search: '',
    })
  })
})
