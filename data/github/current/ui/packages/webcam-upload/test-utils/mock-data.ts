import type {WebcamUploadProps} from '../WebcamUpload'

export function getWebcamUploadProps({allowFileUpload = true}: {allowFileUpload?: boolean} = {}): WebcamUploadProps {
  return {
    formFieldId: 'webcam-upload',
    allowFileUpload,
  }
}
