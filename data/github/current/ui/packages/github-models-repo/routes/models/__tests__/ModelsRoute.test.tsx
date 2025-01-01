import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getModelsRoutePayload} from '../../../test-utils/mock-data'
import {ModelsRoute} from '../ModelsRoute'
import {Route, Routes} from 'react-router-dom'
import {PromptList} from '../../../components/PromptList'

jest.mock('../../../components/PromptList')
const mockPromptList = jest.mocked(PromptList)

describe('ModelsRoute', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('renders overview section', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByRole('heading', {name: 'Overview'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Read the docs'})).toBeInTheDocument()

    expect(screen.getByRole('heading', {name: 'Prompts'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'New prompt'})).toBeInTheDocument()
  })

  test('renders onboarding video banner if feature flag is enabled and banner has not been dismissed', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {
      appPayload: {
        ...appPayload,
        enabled_features: {github_models_onboarding_video_banner: true},
        onboardingVideoBannerDismissed: false,
      },
    })

    expect(screen.getByText('Watch the models demo')).toBeInTheDocument()
  })

  test('does not render onboarding video banner if feature flag is enabled but banner has been dismissed', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {
      appPayload: {
        ...appPayload,
        enabled_features: {github_models_onboarding_video_banner: true},
        onboardingVideoBannerDismissed: true,
      },
    })

    expect(screen.queryByText('Watch the models demo')).not.toBeInTheDocument()
  })

  test('does not render onboarding video banner if feature flag is disabled but banner has not been dismissed', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {
      appPayload: {
        ...appPayload,
        enabled_features: {github_models_onboarding_video_banner: false},
        onboardingVideoBannerDismissed: false,
      },
    })

    expect(screen.queryByText('Watch the models demo')).not.toBeInTheDocument()
  })

  test('renders paid usage banner if feature flag is enabled and banner has not been dismissed', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {
      appPayload: {
        ...appPayload,
        enabled_features: {github_models_billing_ui: true},
        paidUsageBannerDismissed: false,
        current_user: {login: 'monalisa'},
      },
    })

    expect(screen.getByText('Enable paid models usage')).toBeInTheDocument()
  })

  test('does not render paid usage banner if feature flag is enabled but banner has been dismissed', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {
      appPayload: {
        ...appPayload,
        enabled_features: {github_models_billing_ui: true},
        paidUsageBannerDismissed: true,
        current_user: {login: 'monalisa'},
      },
    })

    expect(screen.queryByText('Enable paid models usage')).not.toBeInTheDocument()
  })

  test('does not render paid usage banner if feature flag is disabled', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {
      appPayload: {
        ...appPayload,
        enabled_features: {github_models_billing_ui: false},
        paidUsageBannerDismissed: false,
        current_user: {login: 'monalisa'},
      },
    })

    expect(screen.queryByText('Enable paid models usage')).not.toBeInTheDocument()
  })

  test('renders get started section', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByRole('heading', {name: 'Get started'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Create a sample prompt'})).toBeInTheDocument()
    const comparePrompts = screen.getByRole('link', {name: 'Compare multiple prompts'})
    expect(comparePrompts).toHaveAttribute('href', '/monalisa/smile/models/prompt/compare/main?sample')
    const compareModels = screen.getByRole('link', {name: 'Compare models'})
    expect(compareModels).toHaveAttribute('href', `org/repo/models/registry/model1/playground?compare_to=model2`)
  })

  test('does not render Compare models section when the compareModelsUrl is undefined', () => {
    const appPayload = {...getModelsRoutePayload(), compareModelsUrl: undefined}
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByRole('heading', {name: 'Get started'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Create a sample prompt'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Compare multiple prompts'})).toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'Compare models'})).not.toBeInTheDocument()
  })

  test('renders prompt list with no prompts', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByRole('heading', {name: 'Prompts'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'New prompt'})).toBeInTheDocument()
    expect(mockPromptList).toHaveBeenCalledWith(
      expect.objectContaining({
        prompts: [],
        headerText: '0 prompts found',
        repository: appPayload.repository,
        showViewAll: false,
      }),
      expect.anything(),
    )
  })

  test('renders prompt list with prompts when all prompts are shown', () => {
    const promptNames = ['prompt1', 'prompt2', 'prompt3']
    const appPayload = getModelsRoutePayload(promptNames)
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByRole('heading', {name: 'Prompts'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'New prompt'})).toBeInTheDocument()
    expect(mockPromptList).toHaveBeenCalledWith(
      expect.objectContaining({
        prompts: appPayload.prompts,
        totalPrompts: appPayload.totalPrompts,
        headerText: '3 prompts found',
        repository: appPayload.repository,
        showViewAll: false,
      }),
      expect.anything(),
    )
  })

  test('renders prompt list with prompts when not all prompts are shown', () => {
    const promptNames = ['prompt1', 'prompt2', 'prompt3']
    const appPayload = getModelsRoutePayload(promptNames)
    appPayload.totalPrompts = 5
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByRole('heading', {name: 'Prompts'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'New prompt'})).toBeInTheDocument()
    expect(mockPromptList).toHaveBeenCalledWith(
      expect.objectContaining({
        prompts: appPayload.prompts,
        totalPrompts: appPayload.totalPrompts,
        headerText: 'Showing 3 of 5 prompts',
        repository: appPayload.repository,
        showViewAll: true,
      }),
      expect.anything(),
    )
  })

  test('does not render "New prompt" link when user cannot edit', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {appPayload: {...appPayload, canEdit: false}})

    expect(screen.getByRole('heading', {name: 'Prompts'})).toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'New prompt'})).not.toBeInTheDocument()
  })

  test('renders timeline section', () => {
    const appPayload = getModelsRoutePayload()
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByRole('link', {name: 'Explore 40+ models in the catalog'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Power your prompt with the right model'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Instrument your Actions workflow with models'})).toBeInTheDocument()
  })

  test("renders the read-only banner if the user can't edit", () => {
    const appPayload = getModelsRoutePayload()
    appPayload.canEdit = false
    render(<ModelsRoute />, {appPayload})

    expect(screen.getByText('You do not have access to GitHub Models on this repository')).toBeInTheDocument()
  })

  test('does not render mini getting started and timeline sections when there are no models available', () => {
    const appPayload = getModelsRoutePayload()
    appPayload.compareModelsUrl = undefined
    render(<ModelsRoute />, {appPayload})

    expect(screen.queryByText('Add AI to your project now')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Get API Key'})).not.toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'Explore 40+ models in the catalog'})).not.toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'Power your prompt with the right model'})).not.toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'Instrument your Actions workflow with models'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, opts: TestRenderOptions = {}) {
  return htmlRender(
    <Routes>
      <Route path="/:owner/:repo/models" element={component} />
    </Routes>,
    {
      pathname: '/github/github-models/models',
      ...opts,
    },
  )
}
