import {within, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {modelPath} from '@github-ui/paths'
import ModelInfo from '../ModelInfo'
import {mockModel} from '../../../routes/playground/__tests__/mocks'

describe('ModelInfo', () => {
  test('renders as button', () => {
    const expectedUrl = modelPath(mockModel)

    const {container} = render(<ModelInfo headingLevel="h2" model={mockModel} renderAs="button" />)

    const sidebarInfoEl = within(container).getByTestId('sidebar-info')
    expect(sidebarInfoEl).toBeInTheDocument()
    expect(within(sidebarInfoEl).getByRole('heading', {name: 'About', level: 2})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Model details page'})).toHaveAttribute('href', expectedUrl)
  })

  test('renders as action list item', () => {
    const expectedUrl = modelPath(mockModel)

    const {container} = render(<ModelInfo headingLevel="h2" model={mockModel} renderAs="listitem" />)

    const sidebarInfoEl = within(container).getByTestId('sidebar-info')
    expect(sidebarInfoEl).toBeInTheDocument()
    expect(within(sidebarInfoEl).getByRole('heading', {name: 'About', level: 2})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Model details page'})).toHaveAttribute('href', expectedUrl)
  })

  test('renders the feedback banner when the feature flag is on', () => {
    render(<ModelInfo headingLevel="h2" model={mockModel} renderAs="listitem" />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: true,
        },
      },
    })

    expect(screen.getByText(/Got feedback?/i)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Book a call'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'share feedback via discussion'})).toBeInTheDocument()
  })

  test('does not render the feedback banner when the feature flag is not on', () => {
    render(<ModelInfo headingLevel="h2" model={mockModel} renderAs="listitem" />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
    })

    expect(screen.queryByText(/Got feedback?/i)).not.toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'Book a call'})).not.toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'share feedback via discussion'})).not.toBeInTheDocument()
  })
})
