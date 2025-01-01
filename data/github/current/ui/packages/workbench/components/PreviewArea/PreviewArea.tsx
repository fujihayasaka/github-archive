import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {
  useWorkspaceEditorUIDispatch,
  useWorkspaceEditorUIState,
} from '@github-ui/workspace-editor/contexts/WorkspaceEditorUIContext'
import {UNKNOWN_VALUE} from '@github-ui/workspace-editor/telemetry/constants'
import {withRetries} from '@github-ui/workspace-editor/utilities/with-retries'
import {BannerType, type ConnectedCodespaceData} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {useProvidedRefOrCreate} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useState} from 'react'

import {useCodespaceContext} from '../../contexts/CodespaceContext'
import {useErrors} from '../../contexts/ErrorsContext'
import {usePublishingContext} from '../../contexts/PublishingContext'
import {useWorkbenchPreview} from '../../contexts/WorkbenchPreviewContext'
import {useWorkbenchUI} from '../../contexts/WorkbenchUIContext'
import {useAnalytics} from '../../telemetry/use-analytics'
import type {WorkbenchRoutePayload} from '../../types/workbench-types'
import {CookieBanner} from './CookieBanner'
import {ErrorOverlay} from './ErrorOverlay'
import styles from './PreviewArea.module.css'
import {PreviewOverlay} from './PreviewOverlay'

interface PreviewAreaProps {
  isFetching: boolean
}

export const SPARK_PREVIEW_CONTAINER_ID = 'spark-preview-container'
export const SPARK_PREVIEW_IFRAME_ID = 'spark-preview-iframe'

function isSafariOlderThanCHIPS() {
  const ua = navigator.userAgent
  const isSafari = /^((?!chrome|android).)*safari/i.test(ua)
  const versionMatch = ua.match(/Version\/(\d+)\.(\d+)/)

  if (isSafari && versionMatch) {
    const major = parseInt(versionMatch[1] ?? '0', 10)
    const minor = parseInt(versionMatch[2] ?? '0', 10)
    return major < 18 || (major === 18 && minor < 4) // CHIPS supported in Safari 18.4+
  }

  return false // Not Safari or version unknown
}

function codespaceInfoForTelemetry(codespaceData: ConnectedCodespaceData) {
  return {
    codespaceId: codespaceData.codespaceInfo?.cloud_environment?.guid ?? UNKNOWN_VALUE,
    codespaceState: codespaceData.codespaceState,
    codespaceEnvironmentState: codespaceData.codespaceInfo?.environment_data?.state ?? UNKNOWN_VALUE,
    tunnelId: codespaceData.codespaceInfo?.environment_data?.connection?.tunnelProperties?.tunnelId ?? UNKNOWN_VALUE,
    tunnelClusterId:
      codespaceData.codespaceInfo?.environment_data?.connection?.tunnelProperties?.clusterId ?? UNKNOWN_VALUE,
  }
}

export const PreviewArea = ({isFetching}: PreviewAreaProps) => {
  const overlayOnEmpty = useFeatureFlag('spark_overlay_on_empty')
  const workbenchRefreshOnWsod = useFeatureFlag('copilot_workbench_refresh_on_wsod')
  const workbenchShowConnectionReloadBanner = useFeatureFlag('copilot_workbench_connection_reload_banner')
  const readOnlyPreviewEnabled = useFeatureFlag('copilot_workbench_read_only_preview')
  const verifyPreviewAuthWithoutRedirect = useFeatureFlag('spark_verify_preview_auth_without_redirect')
  const autoFixEmptyApp = useFeatureFlag('spark_auto_fix_empty_app')
  const sendEvent = useAnalytics()

  const {codespaceData} = useCodespaceContext()
  const codespaceName = codespaceData?.codespaceInfo?.environment_data.friendlyName
  const {mobileViewActive, setPreviewUrl, previewBrowserRef, refreshPreview} = useWorkbenchUI()
  const {previewUrl} = usePublishingContext()
  const {acaJwtInfo} = useRoutePayload<WorkbenchRoutePayload>()
  const ref = useProvidedRefOrCreate(previewBrowserRef)

  const {onIFrameLoaded, state, addEmptyAppError, removeEmptyAppError} = useWorkbenchPreview()
  const {overlayErrors} = useErrors()

  const [showCookieBanner, setShowCookieBanner] = useState(false)
  useEffect(() => {
    setShowCookieBanner(isSafariOlderThanCHIPS())
  }, [])

  const [websiteUrl, setWebsiteUrl] = useState<string | null>(null)
  const [readOnlyMode, setReadOnlyMode] = useState<boolean>(false)

  const dispatch = useWorkspaceEditorUIDispatch()

  const {banner} = useWorkspaceEditorUIState()

  const showConnectionReloadBanner = useCallback(() => {
    if (state.viteWsConnected) return
    sendEvent('preview.connection_reload_banner.displayed', {
      timestamp: new Date().toISOString(),
      rootElementEmpty: state.rootElementEmpty,
      viteServerReady: state.viteServerReady,
      viteWsConnected: state.viteWsConnected,
      ...codespaceInfoForTelemetry(codespaceData),
    })

    dispatch({type: 'SET_BANNER', banner: BannerType.CONNECTION_RELOAD})
  }, [codespaceData, dispatch, sendEvent, state.rootElementEmpty, state.viteServerReady, state.viteWsConnected])

  const hideConnectionReloadBanner = useCallback(() => {
    if (banner !== BannerType.CONNECTION_RELOAD) return
    dispatch({type: 'SET_BANNER', banner: undefined})
  }, [banner, dispatch])

  const showEmptyAppError = useCallback(() => {
    if (state.rootElementEmpty) {
      addEmptyAppError()
    }
  }, [addEmptyAppError, state.rootElementEmpty])

  // Update the parent component with the preview URL when it changes
  useEffect(() => {
    if (setPreviewUrl) {
      setPreviewUrl(websiteUrl)
    }
  }, [websiteUrl, setPreviewUrl])

  useEffect(() => {
    async function waitOnServer() {
      if (!state.viteServerReady || codespaceData?.codespaceState !== 'ready') {
        // If the current websiteUrl is not readonly previewUrl, reset it so that it won't render
        if (websiteUrl !== previewUrl) {
          setWebsiteUrl(null)
        }

        if (readOnlyPreviewEnabled && previewUrl !== '' && acaJwtInfo !== undefined) {
          if (readOnlyMode) {
            // If the read-only preview is already set, do not make another request
            return
          }

          // set readOnlyMode to true to prevent multiple requests
          setReadOnlyMode(true)

          const formData = new FormData()
          formData.append('app', acaJwtInfo.appName)
          formData.append('user', acaJwtInfo.userLogin)
          formData.append('payload', acaJwtInfo.payload)
          formData.append('proxyPayload', acaJwtInfo.proxyPayload)

          await fetch(`${previewUrl}`, {
            method: 'POST',
            credentials: 'include', // To set the cookies
            body: formData,
          })

          // Wait a little for the cookies to get set - a safeguard
          // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
          await new Promise(resolve => setTimeout(resolve, 200))

          setWebsiteUrl(previewUrl)
        }

        return
      }

      const tunnelProps = codespaceData?.remoteProvider?.tunnelProps
      const domain = tunnelProps?.domain ?? 'app.github.dev'
      const accessToken = tunnelProps?.connectAccessToken

      if (!accessToken) return

      const url = `https://${codespaceName}-5000.${domain}/`
      const formData = new FormData()
      formData.append('featureFlags', '')
      formData.append('accessToken', accessToken)
      formData.append('skipAntiPhishing', 'on')

      // eslint-disable-next-line no-console
      console.log(`preview iframe auth attempt`)

      if (verifyPreviewAuthWithoutRedirect) {
        formData.append('disableRedirect', '1')
        try {
          await withRetries(
            async retriesLeft => {
              const response = await fetch(`${url}auth/postback/tunnel?tunnel=1`, {
                method: 'POST',
                body: formData,
                credentials: 'include', // For tunnels auth
              })

              // eslint-disable-next-line no-console
              console.log(`preview iframe auth response type: ${response.type}, status: ${response.status}`)

              if (!response.ok) {
                // If the response is not a redirect or not ok, authentication has failed
                throw new Error(`Preview auth error! status: ${response.status}, payload: ${await response.text()}`)
              }

              sendEvent('preview.auth.success', {
                retriesLeft,
                responseType: response.type,
                timestamp: new Date().toISOString(),
                ...codespaceInfoForTelemetry(codespaceData),
              })
            },
            {
              retries: 5,
              retryDelayMs: 500,
              exponentialBackoffFactor: 1.5,
            },
          )
        } catch (error) {
          sendEvent('preview.auth.error', {
            timestamp: new Date().toISOString(),
            error: error instanceof Error ? error.message : String(error),
            ...codespaceInfoForTelemetry(codespaceData),
          })

          // eslint-disable-next-line no-console
          console.error('Failed to authenticate preview:', error)
          dispatch({type: 'SET_BANNER', banner: BannerType.PREVIEW_AUTH_FAILED})
          return
        }
      } else {
        try {
          await withRetries(
            async retriesLeft => {
              const response = await fetch(`${url}auth/postback/tunnel?tunnel=1`, {
                method: 'POST',
                body: formData,
                credentials: 'include', // For tunnels auth
                redirect: 'manual', // redirect need not be followed
              })

              // eslint-disable-next-line no-console
              console.log(`preview iframe auth response type: ${response.type}, status: ${response.status}`)

              if (response.type === 'opaqueredirect') {
                // If the response is an opaque redirect, it means that authentication is successful,
                // with a response code of 302, and set the cookies
                // This is expected behavior
                // eslint-disable-next-line no-console
                console.log('preview iframe redirect skipped.')
              } else if (!response.ok) {
                // If the response is not a redirect or not ok, authentication has failed
                throw new Error(`Preview auth error! status: ${response.status}, payload: ${await response.text()}`)
              }

              sendEvent('preview.auth.success', {
                retriesLeft,
                responseType: response.type,
                timestamp: new Date().toISOString(),
                ...codespaceInfoForTelemetry(codespaceData),
              })
            },
            {
              retries: 5,
              retryDelayMs: 500,
              exponentialBackoffFactor: 1.5,
            },
          )
        } catch (error) {
          sendEvent('preview.auth.error', {
            timestamp: new Date().toISOString(),
            error: error instanceof Error ? error.message : String(error),
            ...codespaceInfoForTelemetry(codespaceData),
          })

          // eslint-disable-next-line no-console
          console.error('Failed to authenticate preview:', error)
          dispatch({type: 'SET_BANNER', banner: BannerType.PREVIEW_AUTH_FAILED})
          return
        }
      }

      // Wait a little for the cookies to get set - a safeguard
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      await new Promise(resolve => setTimeout(resolve, 200))

      // set readonly mode before updating websiteUrl so iframe on load runs
      setReadOnlyMode(false)

      // Set url to load the iframe. Auth cookie is set in the browser by the above fetch
      setWebsiteUrl(url)
    }

    waitOnServer()
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    codespaceName,
    codespaceData,
    codespaceData.codespaceState,
    state.viteServerReady,
    readOnlyPreviewEnabled,
    previewUrl,
    acaJwtInfo,
    verifyPreviewAuthWithoutRedirect,
    dispatch,
    readOnlyMode,
  ])

  // Effect to reload iframe when Vite server disconnects
  useEffect(() => {
    // Only refresh if the feature flag is enabled
    if (workbenchRefreshOnWsod && !readOnlyMode && websiteUrl && !state.viteWsConnected && ref.current) {
      ref.current?.setAttribute('src', '')
      ref.current?.setAttribute('src', websiteUrl)
    }
  }, [ref, websiteUrl, workbenchRefreshOnWsod, state.viteWsConnected, readOnlyMode])

  const readonlyPreviewSet = readOnlyMode && websiteUrl === previewUrl

  // Monitor viteWsConnected and show the connection reload banner if disconnected for more than 5 seconds
  useEffect(() => {
    // Delay function that is automatically cancelled if called again, or if the dependencies change, or when component unmounts
    let delayTimeoutId: NodeJS.Timeout | null = null
    async function delay(ms: number = 2000) {
      await new Promise(resolve => {
        if (delayTimeoutId) clearTimeout(delayTimeoutId)
        delayTimeoutId = setTimeout(resolve, ms)
      })
    }

    if (readonlyPreviewSet || isFetching) {
      // ensure we never show this banner while showing the preview
      hideConnectionReloadBanner()
      return
    }
    if (!workbenchShowConnectionReloadBanner || !websiteUrl || readOnlyMode) return

    if (!state.viteWsConnected) {
      tryReconnectToViteWs()
    } else {
      hideConnectionReloadBanner()
    }

    async function tryReconnectToViteWs() {
      await delay(3000) // Wait 3 seconds to allow auto reconnection

      refreshPreview()
      await delay(3000) // Wait for 3 seconds to allow the iframe to reload

      showConnectionReloadBanner()
    }

    return () => {
      if (delayTimeoutId) clearTimeout(delayTimeoutId)
    }
  }, [
    state.viteWsConnected,
    showConnectionReloadBanner,
    hideConnectionReloadBanner,
    workbenchShowConnectionReloadBanner,
    websiteUrl,
    readOnlyMode,
    readonlyPreviewSet,
    isFetching,
    refreshPreview,
  ])

  useEffect(
    () => {
      // eslint-disable-next-line no-console
      console.log(`Empty app handling conditions:
        isFetching: ${isFetching}
        viteServerReady: ${state.viteServerReady}
        viteWsConnected: ${state.viteWsConnected}
        rootElementEmpty: ${state.rootElementEmpty}
        readOnlyMode: ${readOnlyMode}
        overlayErrors: ${overlayErrors?.length || 0}
        autoFixEmptyApp: ${autoFixEmptyApp}`)

      if (!state.rootElementEmpty) {
        removeEmptyAppError()
      }

      if (!autoFixEmptyApp) {
        return
      }

      if (isFetching || !state.viteServerReady || !state.viteWsConnected) {
        // app not ready
        return
      }

      if (readOnlyMode && overlayErrors?.length) {
        // Not in a fixable state, or has other errors
        return
      }

      let timeoutId: NodeJS.Timeout | null = null
      if (state.rootElementEmpty) {
        sendEvent('preview.auto_fix_empty_app', {
          rootElementEmpty: state.rootElementEmpty,
          timestamp: new Date().toISOString(),
          ...codespaceInfoForTelemetry(codespaceData),
        })

        timeoutId = setTimeout(() => {
          showEmptyAppError()
        }, 3000) // 3 seconds, allowing the app to load
      }

      return () => {
        if (timeoutId) {
          clearTimeout(timeoutId)
        }
      }
    },
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [
      state.rootElementEmpty,
      readOnlyMode,
      addEmptyAppError,
      removeEmptyAppError,
      autoFixEmptyApp,
      isFetching,
      overlayErrors,
      state.viteServerReady,
      state.viteWsConnected,
      codespaceData,
      showEmptyAppError,
    ],
  )

  const hideIframe =
    !readonlyPreviewSet &&
    (!codespaceName ||
      codespaceData.codespaceState !== 'ready' ||
      !state.viteServerReady ||
      !websiteUrl ||
      showCookieBanner)

  const showPreviewOverlay =
    !readonlyPreviewSet &&
    (isFetching || (hideIframe && !showCookieBanner) || (overlayOnEmpty && state.rootElementEmpty))

  // Send Telemetry when Values Change
  useEffect(() => {
    sendEvent('preview.info', {
      isFetching,
      hideIframe,
      showCookieBanner,
      rootElementEmpty: state.rootElementEmpty,
      viteServerReady: state.viteServerReady,
      viteWsConnected: state.viteWsConnected,
      codespaceNamePresent: codespaceName !== undefined,
      websiteUrlPresent: websiteUrl !== null,
      showPreviewOverlay,
      readOnlyPreviewEnabled,
      previewUrl,
      readOnlyState: readOnlyMode,
      ...codespaceInfoForTelemetry(codespaceData),
      timestamp: new Date().toISOString(),
    })
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    codespaceData.codespaceState,
    codespaceName,
    hideIframe,
    isFetching,
    showCookieBanner,
    showPreviewOverlay,
    state.rootElementEmpty,
    state.viteServerReady,
    state.viteWsConnected,
    websiteUrl,
    readOnlyPreviewEnabled,
    previewUrl,
    readOnlyMode,
  ])

  // Clear any runtime errors that may have been created during iteration
  useEffect(() => {
    if (!isFetching) {
      refreshPreview()
    }
  }, [isFetching, refreshPreview])

  return (
    <div
      id={SPARK_PREVIEW_CONTAINER_ID}
      className={clsx(styles.previewContainer, mobileViewActive && styles.previewContainerMobileBackground)}
    >
      {!hideIframe && websiteUrl && (
        <div className={clsx(styles.iframeWrapper, mobileViewActive && styles.mobileView)}>
          <div className={mobileViewActive ? styles.mobileFrame : undefined}>
            <iframe
              id={SPARK_PREVIEW_IFRAME_ID}
              ref={ref}
              src={websiteUrl}
              title="Preview Website"
              style={{width: '100%', height: '100%', border: 'none'}}
              allow="geolocation; microphone; camera; midi; encrypted-media; clipboard-write; web-share"
              // eslint-disable-next-line @eslint-react/dom/no-unsafe-iframe-sandbox
              sandbox="allow-scripts allow-same-origin allow-forms allow-modals allow-popups allow-presentation"
              onLoad={event => !readOnlyMode && onIFrameLoaded(event)}
            />
          </div>
        </div>
      )}
      <PreviewOverlay isLoading={showPreviewOverlay} />
      <ErrorOverlay isFetching={isFetching} />
      {showCookieBanner && <CookieBanner hideCookieBanner={() => setShowCookieBanner(false)} />}
    </div>
  )
}
