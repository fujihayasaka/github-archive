import Webcam from 'react-webcam'
import {isDesktop, isMobile} from '@github-ui/get-os'
import {useCallback, useRef, useState, useEffect} from 'react'
import {testIdProps} from '@github-ui/test-id-props'
import {DeviceCameraIcon, SyncIcon, XIcon} from '@primer/octicons-react'
import {Button, FormControl} from '@primer/react'

import {OverlayContent} from './OverlayContent'

import styles from './WebcamUpload.module.css'

const MAX_WIDTH_OF_CAPTURE_AREA = 320
const SECONDS_FOR_COUNTDOWN = 3
const MAX_FILE_SIZE_IN_MB = 1

export interface WebcamUploadProps {
  formFieldId: string
  allowFileUpload?: boolean
}

export function WebcamUpload({formFieldId, allowFileUpload = true}: WebcamUploadProps) {
  const webcamRef = useRef<Webcam>(null)
  const [image, setImage] = useState<string | null>(null)
  const [showWebcam, setShowWebcam] = useState(false)
  const [countdown, setCountdown] = useState<number | null>(null)
  const [showCheckmark, setShowCheckmark] = useState<boolean>(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [facingMode, setFacingMode] = useState<'user' | 'environment'>('user')
  const [filename, setFilename] = useState<string | null>(null)
  const [type, setType] = useState<'camera' | 'upload' | null>(null)
  const [mimeType, setMimeType] = useState<string | null>(null)
  const [deviceLabel, setDeviceLabel] = useState<string | null>(null)

  useEffect(() => {
    if (!formFieldId) return
    const hiddenInput = document.getElementById(formFieldId) as HTMLInputElement | null
    if (hiddenInput) {
      const imageData = {
        image: image || '',
        metadata: {
          filename,
          type,
          mimeType,
          deviceLabel,
        },
      }

      hiddenInput.value = JSON.stringify(imageData)
    }
  }, [image, formFieldId, filename, type, mimeType, deviceLabel])

  const unmirrorImage = useCallback((mirroredImageSrc: string): Promise<string> => {
    return new Promise(resolve => {
      const newImage = new Image()
      newImage.onload = () => {
        const canvas = document.createElement('canvas')
        canvas.width = newImage.width
        canvas.height = newImage.height
        const ctx = canvas.getContext('2d')

        if (ctx) {
          ctx.translate(canvas.width, 0)
          ctx.scale(-1, 1)
          ctx.drawImage(newImage, 0, 0)

          const unmirroredImageSrc = canvas.toDataURL('image/jpeg')
          resolve(unmirroredImageSrc)
        } else {
          resolve(mirroredImageSrc)
        }
      }
      newImage.src = mirroredImageSrc
    })
  }, [])

  const capture = useCallback(async () => {
    if (webcamRef.current === null) return
    const mirroredImageSrc = webcamRef.current.getScreenshot()
    if (!mirroredImageSrc) return

    const videoTrack = webcamRef.current.stream?.getVideoTracks()[0]

    let finalImageSrc = mirroredImageSrc
    if (facingMode === 'user') {
      finalImageSrc = await unmirrorImage(mirroredImageSrc)
    }

    setImage(finalImageSrc)
    setMimeType('image/jpeg')
    setType('camera')
    setFilename('camera.jpg')
    if (videoTrack) setDeviceLabel(videoTrack.label)
    setCountdown(null)
    setShowCheckmark(true)
    setErrorMessage(null)
  }, [webcamRef, facingMode, unmirrorImage])

  const startCountdown = useCallback(() => {
    setCountdown(SECONDS_FOR_COUNTDOWN)

    const interval = setInterval(() => {
      setCountdown(prev => {
        if (prev === null) return null
        if (prev <= 1) {
          clearInterval(interval)
          capture()
          return null
        }
        return prev - 1
      })
    }, 1000)
  }, [capture])

  const handleUploadFileButtonClick = useCallback(() => {
    const fileUploadInput = document.getElementById('file-upload')
    if (fileUploadInput) {
      setImage(null)
      setErrorMessage(null)
      fileUploadInput.click()
    }
  }, [])

  const handleFileChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files || e.target.files.length === 0) {
      return
    }
    const file = e.target.files[0]
    if (!file) {
      return
    }
    setFilename(file.name)
    setMimeType(file.type)

    if (file.size > MAX_FILE_SIZE_IN_MB * 1024 * 1024) {
      setImage(null)
      setErrorMessage(`File size exeeds ${MAX_FILE_SIZE_IN_MB} MB. Please choose a smaller file.`)
      return
    }

    const reader = new FileReader()
    reader.onloadend = () => {
      if (reader.result) {
        setImage(reader.result as string)
        setType('upload')
        setShowCheckmark(true)
        setErrorMessage(null)
      }
    }
    reader.readAsDataURL(file)
  }, [])

  const toggleFacingMode = () => {
    setFacingMode(prev => (prev === 'user' ? 'environment' : 'user'))
  }

  const captureAreaStyles: React.CSSProperties = {
    width: '100%',
    maxWidth: `${MAX_WIDTH_OF_CAPTURE_AREA}px`,
    aspectRatio: '1',
    borderRadius: '8px',
    overflow: 'hidden',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    border: '2px solid #ccc',
    position: 'relative',
  }

  return (
    <div className="d-flex flex-column flex-items-center flex-justify-center gap-3 width-full">
      {image === null ? (
        <>
          <div className="mt-2" style={captureAreaStyles}>
            {showWebcam ? (
              <div>
                <Webcam
                  videoConstraints={{
                    width: MAX_WIDTH_OF_CAPTURE_AREA,
                    height: MAX_WIDTH_OF_CAPTURE_AREA,
                    facingMode,
                  }}
                  screenshotFormat="image/jpeg"
                  audio={false}
                  className="width-full height-full"
                  ref={webcamRef}
                  mirrored={facingMode === 'user'}
                />
                <OverlayContent content={countdown} />
              </div>
            ) : errorMessage ? (
              <div className="d-flex flex-column flex-items-center flex-justify-center gap-2">
                <XIcon size={96} />
                <div className="text-center px-4">{errorMessage}</div>
              </div>
            ) : (
              <DeviceCameraIcon size={96} />
            )}
          </div>

          <div className="d-flex mb-2">
            <FormControl>
              <FormControl.Label>
                <Button
                  variant="default"
                  onClick={showWebcam ? startCountdown : () => setShowWebcam(true)}
                  className={styles.Button}
                  {...testIdProps('webcam-upload-capture-button')}
                >
                  {showWebcam ? 'Capture photo' : 'Start Camera'}
                </Button>
              </FormControl.Label>
            </FormControl>

            {showWebcam && isMobile() && (
              <FormControl>
                <FormControl.Label>
                  <Button
                    variant="default"
                    onClick={toggleFacingMode}
                    className={styles.Button_1}
                    {...testIdProps('webcam-upload-toggle-facing-mode')}
                  >
                    <SyncIcon />
                  </Button>
                </FormControl.Label>
              </FormControl>
            )}

            {allowFileUpload && isDesktop() && (
              <FormControl>
                <FormControl.Label>
                  <input className="d-none" id="file-upload" type="file" accept="image/*" onChange={handleFileChange} />
                  <Button
                    variant="default"
                    onClick={handleUploadFileButtonClick}
                    className={styles.Button_1}
                    {...testIdProps('webcam-upload-file-upload-button')}
                  >
                    Upload a file
                  </Button>
                </FormControl.Label>
              </FormControl>
            )}
          </div>
        </>
      ) : (
        <>
          <div style={captureAreaStyles}>
            <img src={image} alt="screenshot" className="width-full height-full" style={{objectFit: 'contain'}} />

            {showCheckmark && <OverlayContent content="✓" />}
          </div>

          <div className="d-flex mb-2">
            <FormControl>
              <FormControl.Label>
                <Button
                  variant="default"
                  onClick={() => {
                    setImage(null)
                    setShowWebcam(false)
                    setShowCheckmark(false)
                    setErrorMessage(null)
                  }}
                  className={styles.Button}
                >
                  Restart
                </Button>
              </FormControl.Label>
            </FormControl>
          </div>
        </>
      )}
    </div>
  )
}
