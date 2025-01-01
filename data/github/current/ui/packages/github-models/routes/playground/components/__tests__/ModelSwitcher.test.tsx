import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import ModelSwitcher from '../ModelSwitcher'
import {mockGettingStartedPayload, mockModel, mockO1Model} from '../../__tests__/mocks'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'

const handleSetSidebarTab = jest.fn().mockName('handleSetSidebarTab')
const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

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
        onSelect={() => {}}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
    )
    await user.click(screen.getByLabelText('Switch model'))
    expect(screen.getByText('Switch model')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'View all models'})).toHaveAttribute('href', '/marketplace/models/catalog')
  })

  test('displays models after loading', async () => {
    const manager = {} as PlaygroundManager
    const {user} = render(
      <ModelSwitcher
        model={mockModel}
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

  test('does not include o1 models when restrictedModels does not contain o1 names', async () => {
    const manager = {} as PlaygroundManager
    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        onSelect={() => {}}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      manager,
      {routePayload: {...mockGettingStartedPayload(), restrictedModels: []}},
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

  test('renders compare button variant', async () => {
    const manager = {} as PlaygroundManager
    const onSelect = jest.fn()

    const {user} = render(
      <ModelSwitcher
        model={mockModel}
        onSelect={onSelect}
        onComparisonMode={false}
        handleSetSidebarTab={handleSetSidebarTab}
        variant="compare_button"
      />,
      manager,
    )

    await user.click(screen.getByLabelText('Select model to compare'))

    expect(screen.getByText('Select model')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'View all models'})).toHaveAttribute('href', '/marketplace/models/catalog')

    await user.click(screen.getByText('O1 Mini'))

    expect(onSelect).toHaveBeenCalledWith(mockO1Model)
  })

  describe('when no model is selected', () => {
    // https://github.com/github/models/issues/931
    test('does not render model info button', () => {
      const manager = {} as PlaygroundManager

      render(
        <ModelSwitcher
          variant="default"
          onSelect={() => {}}
          onComparisonMode={false}
          handleSetSidebarTab={handleSetSidebarTab}
        />,
        manager,
      )

      expect(screen.queryByRole('button', {name: 'Show model info'})).not.toBeInTheDocument()
    })
  })
})

function render(
  component: JSX.Element,
  manager: PlaygroundManager,
  opts: TestRenderOptions = {routePayload: mockGettingStartedPayload()},
) {
  return htmlRender(<PlaygroundManagerProvider manager={manager}>{component}</PlaygroundManagerProvider>, opts)
}
