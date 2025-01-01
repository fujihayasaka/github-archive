import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {WebcamUpload} from '../WebcamUpload'
import {getWebcamUploadProps} from '../test-utils/mock-data'

jest.mock('@github-ui/get-os', () => ({
  isMobile: jest.fn().mockReturnValue(false),
  isDesktop: jest.fn().mockReturnValue(true),
}))

test('Renders the WebcamUpload with both capture and upload buttons', () => {
  const props = getWebcamUploadProps({allowFileUpload: true})

  render(<WebcamUpload {...props} />)
  const captureButton = screen.queryByText('Start Camera')
  const uploadButton = screen.queryByText('Upload a file')

  expect(screen.getByTestId('webcam-upload-capture-button')).toBeInTheDocument()
  expect(screen.getByTestId('webcam-upload-file-upload-button')).toBeInTheDocument()
  expect(captureButton).not.toBeNull()
  expect(uploadButton).not.toBeNull()
})

test('Renders the WebcamUpload with only capture button when uploads are disabled', () => {
  const props = getWebcamUploadProps({allowFileUpload: false})

  render(<WebcamUpload {...props} />)
  const uploadButton = screen.queryByText('Upload a file')

  expect(screen.getByTestId('webcam-upload-capture-button')).toBeInTheDocument()
  expect(uploadButton).toBeNull()
})
