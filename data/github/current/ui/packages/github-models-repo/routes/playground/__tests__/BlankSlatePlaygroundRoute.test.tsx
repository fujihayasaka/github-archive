import {BlankSlatePlaygroundRoute} from '../BlankSlatePlaygroundRoute'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {createRepository} from '@github-ui/current-repository/test-helpers'

describe('BlankSlatePlaygroundRoute', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders no playground', () => {
    render(<BlankSlatePlaygroundRoute />, {appPayload: {repository: createRepository()}})

    expect(screen.getByText('No models are available in the playground.')).toBeVisible()
    expect(screen.getByText('Please reach out to your organization administrator to enable models.')).toBeVisible()
    expect(screen.getByRole('link', {name: 'Try the Models Playground in GitHub Marketplace.'})).toHaveAttribute(
      'href',
      '/marketplace/models',
    )
  })

  test('does not render the sidebar collapse icon on load', () => {
    render(<BlankSlatePlaygroundRoute />, {appPayload: {repository: createRepository()}})

    expect(screen.queryByRole('button', {name: 'Expand menu'})).not.toBeInTheDocument()
  })
})
