import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {Model} from '@github-ui/marketplace-common'
import ModelSwitcher from '../ModelSwitcher'
import {mockModel} from '../../__tests__/mocks'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {PlaygroundManagerContext, type PlaygroundManager} from '../../../../utils/playground-manager'

const handleSetSidebarTab = jest.fn().mockName('handleSetSidebarTab')
const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const mockO1Model: Model = {
  id: 'test-o1-model',
  registry: 'azureopenai',
  name: 'o1-mini',
  original_name: 'o1-mini',
  friendly_name: 'O1 Mini',
  publisher: 'Open AI',
  task: 'chat-completion',
  description: 'This is a great model.',
  summary: 'Use this model to do stuff.',
  license: 'MIT',
  logo_url: 'http://example.com/logo.png',
  light_mode_icon: '',
  dark_mode_icon: '',
  tags: ['chat', 'neat'],
  rate_limit_tier: 'medium-ish',
  supported_languages: ['English', 'Mandarin'],
  max_output_tokens: 123,
  max_input_tokens: 456,
  training_data_date: '2022-02-02',
  model_family: 'gpt-4',
  evaluation: 'We think you will love this model.',
  notes: 'This model is great for chat completion.',
  static_model: null,
  supported_input_modalities: ['text', 'postcard'],
  supported_output_modalities: ['fax'],
}

describe('ModelSwitcher', () => {
  beforeEach(() => {
    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: async () => {
        return [mockModel, mockO1Model]
      },
    })
  })

  test('opens the panel when button is clicked', async () => {
    const manager = {} as PlaygroundManager

    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        canUseO1Models
        onSelect={() => {}}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
    )
    await user.click(screen.getByLabelText('Switch model'))
    expect(screen.getByText('Switch model')).toBeInTheDocument()
    expect(screen.getByRole('link')).toHaveAttribute('href', '/marketplace/models')
    expect(screen.getByText('View all models')).toBeInTheDocument()
  })

  test('displays models after loading', async () => {
    const manager = {} as PlaygroundManager
    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        canUseO1Models
        onSelect={() => {}}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
    )
    await user.click(screen.getByLabelText('Switch model'))
    expect(screen.getAllByRole('option')).toHaveLength(2)
    expect(screen.getByText('O1 Mini')).toBeInTheDocument()
  })

  test('does not include o1 models when canUseO1Models is false', async () => {
    const manager = {} as PlaygroundManager
    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        canUseO1Models={false}
        onSelect={() => {}}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
    )
    await user.click(screen.getByLabelText('Switch model'))
    expect(screen.getAllByRole('option')).toHaveLength(1)
    expect(screen.queryByText('O1 Mini')).not.toBeInTheDocument()
  })

  test('filters models based on search input', async () => {
    const manager = {} as PlaygroundManager
    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        canUseO1Models
        onSelect={() => {}}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
    )
    await user.click(screen.getByLabelText('Switch model'))
    expect(screen.getByText('O1 Mini')).toBeInTheDocument()
    expect(screen.getAllByRole('option')).toHaveLength(2)

    const searchInput = screen.getByRole('textbox', {name: 'Filter models'})
    await user.click(searchInput)
    await user.keyboard('Test')
    expect(screen.getAllByRole('option')).toHaveLength(1)
    expect(screen.queryByText('O1 Mini')).not.toBeInTheDocument()
  })

  test('calls back when the main model is changed', async () => {
    const manager = {} as PlaygroundManager
    const onSelect = jest.fn()
    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        canUseO1Models
        onSelect={onSelect}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
    )
    await user.click(screen.getByLabelText('Switch model'))
    await user.click(screen.getByText('O1 Mini'))

    expect(onSelect).toHaveBeenCalledWith(mockO1Model)
  })

  test('model info button displays model info in comparison mode', async () => {
    const manager = {} as PlaygroundManager

    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        canUseO1Models
        onSelect={() => {}}
        onComparisonMode
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
    )

    const showModelInfoButton = screen.getByTestId('model-info-button')
    expect(showModelInfoButton).toBeInTheDocument()

    await user.click(showModelInfoButton)

    expect(screen.getByRole('heading', {name: 'Details', level: 1})).toBeInTheDocument()

    // Close model info menu:
    await user.keyboard('{Escape}')
    expect(screen.queryByRole('menu', {name: 'Show model info'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, manager: PlaygroundManager) {
  return htmlRender(<PlaygroundManagerContext.Provider value={manager}>{component}</PlaygroundManagerContext.Provider>)
}
