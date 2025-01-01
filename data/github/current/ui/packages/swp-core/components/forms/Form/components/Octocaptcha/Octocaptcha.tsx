import {CheckCircleIcon} from '@primer/octicons-react'
import {type ReactNode, useCallback, useContext, useEffect, useState} from 'react'

import {OCTOCAPTCHA_TIMEOUT} from './config'
import {OctocaptchaContext} from './OctocaptchaContext'

export type OctocaptchaProps = {
  className?: string
  onComplete?: (options: {token: string}) => void
  onLoadError?: (error: Error) => void

  /**
   * The number of milliseconds to wait before considering the captcha load to have timed out.
   * Defaults to 30 seconds.
   */
  timeoutAfter?: number
}

export function Octocaptcha(props: OctocaptchaProps) {
  const {hostName, originPage} = useContext(OctocaptchaContext)

  // The full URL of the octocaptcha iframe (including query parameters)
  const [octocaptchaUrl, setOctocaptchaUrl] = useState<string | undefined>(undefined)

  const [isOctocaptchaReady, setOctocaptchaReady] = useState(false)
  const [isOctocaptchaSupressed, setOctocaptchaSupressed] = useState(false)
  const [hasOctocaptchaFailedToLoad, setHasOctocaptchaFailedToLoad] = useState(false)

  const [token, setToken] = useState('')

  const onCaptchaTimeout = useCallback(() => {
    if (!isOctocaptchaReady && !isOctocaptchaSupressed) {
      setHasOctocaptchaFailedToLoad(true)

      if (props.onLoadError !== undefined) {
        props.onLoadError(new Error('Octocaptcha did not load and timed out'))
      }
    }
  }, [isOctocaptchaReady, isOctocaptchaSupressed, props])

  const onMessageHandler = useCallback(
    (event: MessageEvent) => {
      const originHost = new URL(event.origin, window.location.origin).host
      if (originHost !== hostName) {
        return
      }

      const {data} = event

      if (data.event === 'captcha-complete') {
        setToken(data.sessionToken)

        if (props.onComplete !== undefined) {
          props.onComplete({token: data.sessionToken})
        }
      }

      if (data.event === 'captcha-loaded') {
        setOctocaptchaReady(true)
      }

      if (data.event === 'captcha-suppressed') {
        setOctocaptchaSupressed(true)
      }
    },
    [props, hostName],
  )

  useEffect(() => {
    const qs = new URLSearchParams({origin: window.location.origin, responsive: 'true', require_ack: 'true'})

    if (originPage !== undefined) {
      qs.append('origin_page', originPage)
    }

    const protocol = hostName.includes('localhost') ? 'http://' : 'https://'
    setOctocaptchaUrl(`${protocol}${hostName}?${qs.toString()}`)
  }, [originPage, hostName])

  useEffect(() => {
    window.addEventListener('message', onMessageHandler)

    return () => {
      window.removeEventListener('message', onMessageHandler)
    }
  }, [onMessageHandler])

  useEffect(() => {
    const timeout = setTimeout(onCaptchaTimeout, props.timeoutAfter ?? OCTOCAPTCHA_TIMEOUT)

    return () => {
      clearTimeout(timeout)
    }
  }, [props.timeoutAfter, onCaptchaTimeout])

  return (
    <div className={`position-relative ${props.className ?? ''}`} style={{height: 310}}>
      {!isOctocaptchaReady && (
        <LoadingSkeleton>
          <img src="/images/spinners/octocat-spinner-128.gif" alt="Loading CAPTCHA..." width={64} height={64} />
        </LoadingSkeleton>
      )}

      {isOctocaptchaSupressed && (
        <LoadingSkeleton>
          <CheckCircleIcon size={64} aria-label="Account has been verified. Please continue." />
        </LoadingSkeleton>
      )}

      {octocaptchaUrl !== undefined && (
        // eslint-disable-next-line @eslint-react/dom/no-missing-iframe-sandbox
        <iframe
          src={octocaptchaUrl}
          title="Please verify by completing this captcha."
          className="d-block position-absolute height-full width-full top-0 left-0 border-0"
          style={isOctocaptchaReady && !isOctocaptchaSupressed ? {} : {height: 0, visibility: 'hidden'}}
        />
      )}

      {hasOctocaptchaFailedToLoad ? (
        <input type="hidden" id="error_loading_captcha" name="error_loading_captcha" defaultValue="1" />
      ) : (
        <input className="d-none" name="octocaptcha-token" required defaultValue={token} />
      )}
    </div>
  )
}

const LoadingSkeleton = (props: {children: ReactNode}) => {
  return (
    <div
      className="position-absolute height-full width-full top-0 left-0 d-flex flex-justify-center flex-items-center border rounded-2"
      style={{backgroundColor: 'var(--brand-color-canvas-default)', color: 'var(--brand-color-success-fg)'}}
    >
      {props.children}
    </div>
  )
}
