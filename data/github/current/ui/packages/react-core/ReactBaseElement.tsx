import {target} from '@github/catalyst'
import {createRoot, hydrateRoot} from 'react-dom/client'
import type {createRoot as createRootType, hydrateRoot as hydrateRootType, Root} from 'react-dom/client'
import React from 'react'
import ReactProfilingMode from '@github-ui/react-profiling-mode'
import {EXPECTED_ERRORS} from './expected-errors'
import {isStaff, sendStats} from '@github-ui/stats'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import type {ErrorContext} from '@github-ui/failbot'

type ReactDOM = {
  createRoot: typeof createRootType
  hydrateRoot: typeof hydrateRootType
}

const REACT_INVARIANT_ERROR_REGEX = /Minified React error #(?<invariant>\d+)/
const EXPECTED_INVARIANTS = ['419', '421']

function isDevelopmentOrStaffUser() {
  return process.env.NODE_ENV === 'development' || isStaff()
}

export abstract class ReactBaseElement<T> extends HTMLElement {
  @target declare embeddedData: HTMLScriptElement | undefined
  @target declare ssrError: HTMLScriptElement | undefined
  @target declare reactRoot: HTMLElement | undefined
  private root: Root | undefined

  abstract nameAttribute: string
  abstract getReactNode(
    embeddedData: T,
    onError: (error: Error, context?: ErrorContext) => void,
  ): Promise<React.ReactNode>

  protected get name() {
    return this.getAttribute(this.nameAttribute) as string
  }

  private get embeddedDataText() {
    const text = this.embeddedData?.textContent

    if (!text) {
      throw new Error(`No embedded data provided for react element ${this.name}`)
    }

    return text
  }

  get hasSSRContent() {
    return this.getAttribute('data-ssr') === 'true'
  }

  get attemptedSSR() {
    return this.getAttribute('data-attempted-ssr') === 'true'
  }

  connectedCallback() {
    this.renderReact()
  }

  disconnectedCallback() {
    this.root?.unmount()
    this.root = undefined
  }

  private async renderReact() {
    if (!this.reactRoot) throw new Error('No react root provided')
    let reactDom: ReactDOM = {
      createRoot,
      hydrateRoot,
    }

    // Override the react-dom import if we're in profiling mode
    if (ReactProfilingMode.isEnabled()) {
      reactDom = await this.getReactDomWithProfiling()
    }

    let hydrationError = false
    const onError = (error: Error, context: ErrorContext = {}) => {
      hydrationError = true

      const ctx = {
        critical: true,
        reactAppName: this.name,
        ...context,
      }

      setTimeout(() => {
        reportError(error, ctx)
      })
    }
    const embeddedData = JSON.parse(this.embeddedDataText) as T
    const ssrErrorText = this.ssrError?.textContent
    const node = await this.getReactNode(embeddedData, onError)
    const baseNode = <React.StrictMode>{node}</React.StrictMode>

    if (ssrErrorText) {
      this.logSSRError(ssrErrorText)
    }

    if (this.hasSSRContent) {
      const temporaryStyleTags = [
        /**
         * Styled-components automatically looks for style tags to hydrate on first page load, but will not detect them
         * if they are added after the initial page load. This causes a hydration error because React isn't expecting
         * a style tag within the app. To work around this, we need to manually move the style tags to the head before
         * hydrating the app.
         *
         * During hydration, styled-components will create a new style tag which matches the one we moved to the head.
         * This means that after hydration, we can safely remove the style tag we manually moved to the head.
         */
        ...this.querySelectorAll('style[data-styled="true"]'),
        /**
         * When using Vite, we inject temporary <link> tags into the SSRd content to provide CSS Module styles on page
         * load. These tags can be removed after hydration, but need to be moved to the <head> initially to avoid
         * hydration errors. After hydration, the JS version of these CSS modules will be loaded, providing the same
         * styles with HMR support.
         */
        ...this.querySelectorAll('link[data-remove-after-hydration="true"]'),
      ]
      // move the temporary tags to the head to avoid hydration errors, while keeping the styles applied to SSRd content
      for (const tag of temporaryStyleTags) {
        document.head.appendChild(tag)
      }

      // Hydrate the react app
      // onRecoverableError is disabled until we have a react version with this fix in:
      // https://github.com/facebook/react/pull/25692
      this.root = reactDom.hydrateRoot(this.reactRoot, baseNode, {
        onRecoverableError: (error, errorInfo) => {
          if (!(error instanceof Error)) return

          const match = REACT_INVARIANT_ERROR_REGEX.exec(error.message)
          const invariant = String(match?.groups?.invariant)
          hydrationError = !EXPECTED_INVARIANTS.includes(invariant)

          sendStats({
            incrementKey: 'REACT_HYDRATION_ERROR',
            incrementTags: {
              appName: this.name,
              invariant,
            },
          })

          /** Log unexpected hydration errors in development or production for a staff user */
          if (!hydrationError || !isDevelopmentOrStaffUser()) return
          // eslint-disable-next-line no-console
          console.groupCollapsed(
            `%c⚠️ Recoverable hydration error - ${error.message}`,
            'background: rgba(255, 193, 7, 0.2); font-weight: bold; padding: 4px; border: 1px solid rgba(255, 193, 7, 0.5); border-radius: 4px;',
            'This is only visible to staff users and is safe to ignore. Reach out to #react for help understanding and fixing these hydration errors',
          )
          if (error.cause) {
            // eslint-disable-next-line no-console
            console.warn('cause', error.cause)
          }
          if (errorInfo.componentStack) {
            // eslint-disable-next-line no-console
            console.warn('componentStack', errorInfo.componentStack)
          }
          if (errorInfo.digest) {
            // eslint-disable-next-line no-console
            console.warn('digest', errorInfo.digest)
          }
          // eslint-disable-next-line no-console
          console.groupEnd()
        },
      })

      // Remove the manually moved style tags after hydration
      if (temporaryStyleTags.length > 0) {
        // Wait until things are idle to remove the style tag. If we do it immediately, we can cause a flash of unstyled content.
        requestIdleCallback(() => {
          // styles could have already been removed by Turbo if a navigation happens quickly. Only remove it from the DOM if it's still there.
          for (const tag of temporaryStyleTags) {
            tag.parentElement?.removeChild(tag)
          }
        })
      }

      sendStats({
        incrementKey: 'REACT_RENDER',
        incrementTags: {
          appName: this.name,
          csr: false,
          error: hydrationError,
          ssr: true,
          ssrError: false,
        },
      })
    } else {
      this.root = reactDom.createRoot(this.reactRoot)
      this.root.render(baseNode)

      sendStats({
        incrementKey: 'REACT_RENDER',
        incrementTags: {
          appName: this.name,
          csr: true,
          error: hydrationError,
          ssr: this.attemptedSSR,
          ssrError: !!this.ssrError,
        },
      })
    }

    this.classList.add('loaded')
  }

  private getReactDomWithProfiling() {
    return import('react-dom/profiling') as unknown as Promise<ReactDOM>
  }

  private logSSRError(ssrErrorText: string) {
    if (!isDevelopmentOrStaffUser()) return
    if (EXPECTED_ERRORS[ssrErrorText]) {
      // eslint-disable-next-line no-console
      return console.error('SSR failed with an expected error:', EXPECTED_ERRORS[ssrErrorText])
    }

    try {
      const error = JSON.parse(ssrErrorText) as PlatformJavascriptError
      const stacktrace = parseFailbotStacktrace(error)
      // eslint-disable-next-line no-console
      console.error('Error During Alloy SSR:', `${error.type}: ${error.value}\n`, error, stacktrace)
    } catch {
      /**
       * In the event we couldn't log the error, we should not break the application
       */
      // eslint-disable-next-line no-console
      console.error('Error During Alloy SSR:', ssrErrorText, 'unable to parse as json')
    }
  }
}

function parseFailbotStacktrace(error: PlatformJavascriptError) {
  if (!error.stacktrace) return ''
  let prefix = '\n '
  const stack = error.stacktrace.map((frame: PlatformStackframe) => {
    const {function: func, filename, lineno, colno} = frame
    const line = `${prefix} at ${func} (${filename}:${lineno}:${colno})`
    prefix = ' '
    return line
  })
  return stack.join('\n')
}
