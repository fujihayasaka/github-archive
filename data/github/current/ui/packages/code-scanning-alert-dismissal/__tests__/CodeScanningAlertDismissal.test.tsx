import {screen, fireEvent, within, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CodeScanningAlertDismissal} from '../CodeScanningAlertDismissal'
import {
  getCodeScanningAlertDismissalProps,
  getCodeScanningAlertDismissalPropsDelegatedDismissal,
} from '../test-utils/mock-data'
import {verifiedFetch} from '@github-ui/verified-fetch'

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch')
const mockedVerifiedFetch = jest.mocked(verifiedFetch)

const resp = Promise.resolve({ok: true} as Response)
mockedVerifiedFetch.mockReturnValue(resp)

describe('Code Scanning Alert Dismissal', () => {
  it('correctly renders the CodeScanningAlertDismissal component', () => {
    const props = getCodeScanningAlertDismissalProps()
    render(<CodeScanningAlertDismissal {...props} />)

    const button = screen.getByTestId('code-scanning-alert-dismissal-toggle-button')

    expect(button).toBeInTheDocument()

    expect(screen.queryByTestId('code-scanning-alert-dismissal-form')).toBeNull()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)
    expect(screen.getByTestId('code-scanning-alert-dismissal-form')).toBeInTheDocument()

    const reasons = screen.getAllByTestId('code-scanning-alert-dismissal-reason')
    expect(reasons).toHaveLength(Object.keys(props.alertClosureReasons).length)

    expect(screen.getByTestId('code-scanning-alert-dismissal-comment')).toBeInTheDocument()

    const selectedReason = within(reasons[0]!).getByRole('radio')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(selectedReason)

    expect(selectedReason).toBeChecked()
    expect(screen.getByTestId('code-scanning-alert-dismissal-comment')).toBeInTheDocument()
  })

  it('shows error when reason is not selected and form is submitted', async () => {
    const props = getCodeScanningAlertDismissalProps()
    render(<CodeScanningAlertDismissal {...props} />)

    const button = screen.getByTestId('code-scanning-alert-dismissal-toggle-button')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    const submitButton = screen.getByTestId('code-scanning-alert-dismissal-submit-button')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(submitButton)

    expect(screen.getByText('Please select a dismissal reason')).toBeInTheDocument()
    expect(mockedVerifiedFetch).not.toHaveBeenCalled()
  })

  describe('Delegated alert dismissal is on', () => {
    it('shows error when comment is empty and form is submitted', async () => {
      const props = getCodeScanningAlertDismissalPropsDelegatedDismissal()
      render(<CodeScanningAlertDismissal {...props} />)

      const button = screen.getByTestId('code-scanning-alert-dismissal-toggle-button')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(button)

      const reasons = screen.getAllByTestId('code-scanning-alert-dismissal-reason')

      const selectedReason = within(reasons[0]!).getByRole('radio')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(selectedReason)

      const comment = screen.getByTestId('code-scanning-alert-dismissal-comment-textarea')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.change(comment, {target: {value: ''}})

      const submitButton = screen.getByTestId('code-scanning-alert-dismissal-submit-button')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(submitButton)

      expect(screen.getByText('This field is required')).toBeInTheDocument()
      expect(mockedVerifiedFetch).not.toHaveBeenCalled()
    })

    it('submits form when comment is not empty', async () => {
      const props = getCodeScanningAlertDismissalPropsDelegatedDismissal()
      render(<CodeScanningAlertDismissal {...props} />)

      const button = screen.getByTestId('code-scanning-alert-dismissal-toggle-button')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(button)

      const reasons = screen.getAllByTestId('code-scanning-alert-dismissal-reason')

      const selectedReason = within(reasons[0]!).getByRole('radio')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(selectedReason)

      const comment = screen.getByTestId('code-scanning-alert-dismissal-comment-textarea')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.change(comment, {target: {value: 'not empty'}})

      const submitButton = screen.getByTestId('code-scanning-alert-dismissal-submit-button')

      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(submitButton)
      expect(screen.queryByText('This field is required')).not.toBeInTheDocument()
      await waitFor(() => expect(mockedVerifiedFetch).toHaveBeenCalledTimes(1))
    })
  })
})
