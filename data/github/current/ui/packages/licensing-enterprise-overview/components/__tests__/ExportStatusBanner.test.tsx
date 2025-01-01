import {render, screen, within} from '@testing-library/react'
import {ExportStatusBanner} from '../ExportStatusBanner'
import {ExportJobState} from '../../types/export-job-state'

const renderComponent = (props = {}) => {
  const defaultProps = {
    exportJobState: ExportJobState.Inactive,
    onDismissClick: jest.fn(),
    emailNotificationMessage: '',
    showDownloadButtonOnReady: false,
    onDownloadButtonClick: jest.fn(),
  }

  return render(<ExportStatusBanner {...defaultProps} {...props} />)
}

test('renders the Pending state with no email notification message', () => {
  renderComponent({
    exportJobState: ExportJobState.Pending,
    emailNotificationMessage: undefined,
  })

  const bannerEl = screen.getByTestId('export-status-banner-pending')
  expect(bannerEl).toBeInTheDocument()
  expect(bannerEl).toHaveTextContent('Generating CSV')
  expect(bannerEl).toHaveTextContent('The CSV report is being generated.')

  // assert spinner is shown
  const spinnerEl = within(bannerEl)
    .getAllByTestId('export-status-pending-spinner')
    .find(el => el.tagName.toLowerCase() === 'svg')
  expect(spinnerEl).toBeInTheDocument()
})

test('renders the Pending state with an email notification message', () => {
  renderComponent({
    exportJobState: ExportJobState.Pending,
    emailNotificationMessage: 'Email notification message',
  })

  const bannerEl = screen.getByTestId('export-status-banner-pending')
  expect(bannerEl).toBeInTheDocument()
  expect(bannerEl).toHaveTextContent('Generating CSV')
  expect(bannerEl).toHaveTextContent('Email notification message')

  // assert spinner is shown
  const spinnerEl = within(bannerEl)
    .getAllByTestId('export-status-pending-spinner')
    .find(el => el.tagName.toLowerCase() === 'svg')
  expect(spinnerEl).toBeInTheDocument()
})

test('renders the Ready state with no download button', () => {
  renderComponent({
    exportJobState: ExportJobState.Ready,
    showDownloadButtonOnReady: false,
  })

  const bannerEl = screen.getByTestId('export-status-banner-ready')
  expect(bannerEl).toBeInTheDocument()
  expect(bannerEl).toHaveTextContent('CSV report generation complete')
  expect(bannerEl).toHaveTextContent('Downloaded CSV')
})

test('renders the Ready state with a download button', () => {
  renderComponent({
    exportJobState: ExportJobState.Ready,
    showDownloadButtonOnReady: true,
  })

  const bannerEl = screen.getByTestId('export-status-banner-ready')
  expect(bannerEl).toBeInTheDocument()
  expect(bannerEl).toHaveTextContent('CSV report generation complete')

  const button = within(bannerEl).getAllByText('Download CSV')[0]
  expect(button).toBeInTheDocument()
})

test('renders the Error state', () => {
  renderComponent({
    exportJobState: ExportJobState.Error,
  })

  const bannerEl = screen.getByTestId('export-status-banner-error')
  expect(bannerEl).toBeInTheDocument()

  expect(bannerEl).toHaveTextContent('The CSV report could not be generated. Please try again later.')
})

test('calls onDismissClick when the dismiss button is clicked', () => {
  const onDismissClick = jest.fn()
  renderComponent({
    exportJobState: ExportJobState.Ready,
    onDismissClick,
  })

  const bannerEl = screen.getByTestId('export-status-banner-ready')
  const button = within(bannerEl).getAllByRole('button')[0]
  expect(button).toBeInTheDocument()
  button?.click()

  expect(onDismissClick).toHaveBeenCalledTimes(1)
})

test('calls onDownloadButtonClick when the download button is clicked', () => {
  const onDownloadButtonClick = jest.fn()
  renderComponent({
    exportJobState: ExportJobState.Ready,
    showDownloadButtonOnReady: true,
    onDownloadButtonClick,
  })

  const bannerEl = screen.getByTestId('export-status-banner-ready')
  const button = within(bannerEl).getAllByText('Download CSV')[0]
  button?.click()

  expect(onDownloadButtonClick).toHaveBeenCalledTimes(1)
})
