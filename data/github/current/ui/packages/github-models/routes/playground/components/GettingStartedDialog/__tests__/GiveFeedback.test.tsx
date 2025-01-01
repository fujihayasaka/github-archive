import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {feedbackUrl, GiveFeedback} from '../GiveFeedback'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

describe('GiveFeedback', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when not on mobile and lifecycle_label_name_updates is disabled', () => {
    mockIsFeatureEnabled.mockReturnValue(false)

    const {container} = render(<GiveFeedback />)

    expect(within(container).queryByText('Thoughts on GitHub Models?')).not.toBeInTheDocument()
    expect(within(container).queryByText('Preview')).not.toBeInTheDocument()
    expect(within(container).getByText('Beta')).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('renders when on mobile and lifecycle_label_name_updates is disabled', () => {
    mockIsFeatureEnabled.mockReturnValue(false)

    const {container} = render(<GiveFeedback mobile />)

    expect(within(container).getByText('Thoughts on GitHub Models?')).toBeInTheDocument()
    expect(within(container).queryByText('Preview')).not.toBeInTheDocument()
    expect(within(container).getByText('Beta')).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('renders when not on mobile and lifecycle_label_name_updates is enabled', () => {
    mockIsFeatureEnabled.mockImplementation(flag => flag === 'lifecycle_label_name_updates')

    const {container} = render(<GiveFeedback />)

    expect(within(container).queryByText('Thoughts on GitHub Models?')).not.toBeInTheDocument()
    expect(within(container).getByText('Preview')).toBeInTheDocument()
    expect(within(container).queryByText('Beta')).not.toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('renders when on mobile and lifecycle_label_name_updates is enabled', () => {
    mockIsFeatureEnabled.mockImplementation(flag => flag === 'lifecycle_label_name_updates')

    const {container} = render(<GiveFeedback mobile />)

    expect(within(container).getByText('Thoughts on GitHub Models?')).toBeInTheDocument()
    expect(within(container).getByText('Preview')).toBeInTheDocument()
    expect(within(container).queryByText('Beta')).not.toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })
})
