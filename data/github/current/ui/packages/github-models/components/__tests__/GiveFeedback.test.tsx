import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {GiveFeedback} from '../GiveFeedback'
import {feedbackUrl} from '../../constants'

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

  test('does not render Give feedback when on playground', () => {
    const {container} = render(<GiveFeedback playground />)

    expect(within(container).queryByRole('link', {name: 'Give feedback'})).not.toBeInTheDocument()
  })

  test('renders Give feedback when not on playground', () => {
    const {container} = render(<GiveFeedback />)

    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('does not render Give feedback link when on playground and on mobile', () => {
    const {container} = render(<GiveFeedback playground mobile />)

    expect(within(container).queryByRole('link', {name: 'Give feedback'})).not.toBeInTheDocument()
  })

  test('renders Give feedback link when not on playground and on mobile', () => {
    const {container} = render(<GiveFeedback mobile />)

    expect(within(container).getByRole('link', {name: 'Give feedback'})).toBeInTheDocument()
  })
})
