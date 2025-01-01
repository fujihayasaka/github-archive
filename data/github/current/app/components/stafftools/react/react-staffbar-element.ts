import type {ReactAppElement} from '@github-ui/react-core/ReactAppElement'
import {controller, target} from '@github/catalyst'
import {formatBytes} from '../../../assets/modules/github/format-bytes'
import type {SoftNavPayloadEvent} from '@github-ui/soft-nav/events'

type PayloadBase = {
  size: number
  name: string
  hasSSRContent: boolean
  ssrError: boolean
}

type PartialPayload = {
  type: 'partial'
  embeddedData: unknown
} & PayloadBase

type AppPayload = {
  type: 'app'
  payload: unknown
  appPayload: unknown
  isDataRouterEnabled: boolean
} & PayloadBase

@controller
class ReactStaffbarElement extends HTMLElement {
  @target declare payloadSize: HTMLSpanElement
  @target declare logPayloadButton: HTMLButtonElement
  @target declare speedscopeLink: HTMLAnchorElement
  @target declare payloadText: HTMLSpanElement
  @target declare ssrLink: HTMLSpanElement
  @target declare ssrError: HTMLSpanElement
  @target declare viewPayloadButton: HTMLButtonElement
  @target declare enableReactScanButton: HTMLButtonElement | null
  @target declare dataRouterLink: HTMLAnchorElement

  payloads: Array<PartialPayload | AppPayload> = []
  reactScanEnabled: boolean = false

  connectedCallback() {
    document.addEventListener('soft-nav:payload', this.onSoftNavPayload)
    document.addEventListener('turbo:load', this.onTurboLoad)

    this.updateReactVersion()

    this.reactScanEnabled = window.location.search.includes('_reactscan=true')
    this.setReactScanButtonAttributes()
  }

  disconnectedCallback() {
    document.removeEventListener('soft-nav:payload', this.onSoftNavPayload)
    document.removeEventListener('turbo:load', this.onTurboLoad)
  }

  updateReactVersion() {
    const reactStaffbar = document.querySelector('#staffbar-react-version')
    if (!reactStaffbar) return
    // Trim the date off the end of React's version string to make it fit in the staffbar a little better.
    const trimmedReactVersion = REACT_VERSION.replace(/^(.*)-\d+$/, '$1')
    reactStaffbar.textContent = `| React ${trimmedReactVersion}`
  }

  onSoftNavPayload = (event: SoftNavPayloadEvent) => {
    const {payload, appPayload} = event
    this.checkReactApp(payload, appPayload)
    this.updatePayload()
  }

  onTurboLoad = () => {
    this.extractPartialPayloads()
    this.updatePayload()
  }

  checkReactApp(payload: unknown, appPayload: unknown) {
    const reactApp = document.querySelector<ReactAppElement>('react-app') || document.querySelector('projects-v2')

    if (reactApp) {
      const appName = reactApp.getAttribute('app-name') || ''

      // filter out any previous entries for this app
      this.payloads = this.payloads.filter(reactPayload => reactPayload.type !== 'app')

      const tempPayload: AppPayload = {
        name: appName,
        payload,
        appPayload,
        type: 'app',
        size: this.getPayloadChars(payload, appPayload),
        ssrError: !!reactApp.ssrError,
        hasSSRContent: reactApp.hasSSRContent,
        isDataRouterEnabled: reactApp.isDataRouterEnabled,
      }

      this.payloads.push(tempPayload)
    }
  }

  updatePayload() {
    let hasSSRErrorRollup = false
    let hasSSRContentRollup = false
    let hasDataRouterEnabledRollup = false
    let amountOfChars = 0
    const onClickConsoleLogs: Array<() => void> = []

    for (const payload of this.payloads) {
      if (payload.ssrError) hasSSRErrorRollup = true
      if (payload.hasSSRContent) hasSSRContentRollup = true
      if ('isDataRouterEnabled' in payload && payload.isDataRouterEnabled) hasDataRouterEnabledRollup = true
      amountOfChars += payload.size

      if (payload.type === 'app') {
        onClickConsoleLogs.push(() => {
          // eslint-disable-next-line no-console
          console.group(`React App - ${payload.name}`)
          // eslint-disable-next-line no-console
          console.log({payload: payload.payload, appPayload: payload.appPayload})
          // eslint-disable-next-line no-console
          console.groupEnd()
        })
      } else if (payload.type === 'partial') {
        onClickConsoleLogs.push(() => {
          // eslint-disable-next-line no-console
          console.group(`React Partial - ${payload.name}`)
          // eslint-disable-next-line no-console
          console.log(payload.embeddedData)
          // eslint-disable-next-line no-console
          console.groupEnd()
        })
      }
    }

    // Update payload size
    const payloadSize = formatBytes(amountOfChars, 2)
    this.payloadSize.textContent = payloadSize
    this.viewPayloadButton.ariaLabel = `${payloadSize}, React payload size`
    // eslint-disable-next-line i18n-text/no-en
    this.payloadText.textContent = `The payload size is ${payloadSize}.`

    // Update SSR info
    const showSSRError = hasSSRErrorRollup
    const showSSRSuccess = hasSSRContentRollup && !showSSRError

    this.ssrLink.hidden = !showSSRSuccess
    this.ssrError.hidden = !showSSRError
    this.dataRouterLink.hidden = !hasDataRouterEnabledRollup

    // Misc element updates
    this.updateSpeedscopeLink()
    this.updateVisibility()

    // Update click events
    if (this.payloads.length > 0) {
      const payloadButton = this.logPayloadButton
      if (payloadButton) {
        payloadButton.onclick = () => {
          // eslint-disable-next-line no-console
          console.group('React Payloads')
          for (const onClickConsoleLog of onClickConsoleLogs) {
            onClickConsoleLog()
          }
          // eslint-disable-next-line no-console
          console.groupEnd()
        }
      }

      if (this.enableReactScanButton) {
        this.enableReactScanButton.onclick = () => {
          this.toggleReactScan()
        }
      }
    }
  }

  extractPartialPayloads() {
    const reactPartials: NodeListOf<ReactAppElement> = document.querySelectorAll('react-partial')

    for (const reactPartial of reactPartials) {
      const partialName = reactPartial.getAttribute('partial-name')!
      const embeddedDataElement = reactPartial.querySelector(
        `react-partial[partial-name="${partialName}"] > script[type="application/json"][data-target="react-partial.embeddedData"]`,
      )

      const embeddedDataText = embeddedDataElement?.textContent || '{}'
      const embeddedData = JSON.parse(embeddedDataText)
      const tempPayload: PartialPayload = {
        name: partialName,
        embeddedData,
        size: embeddedDataText.length,
        type: 'partial',
        ssrError: !!reactPartial.ssrError,
        hasSSRContent: reactPartial.hasSSRContent,
      }

      this.payloads.push(tempPayload)
    }
  }

  getPayloadChars(payload: unknown, appPayload: unknown) {
    return (payload ? JSON.stringify(payload).length : 0) + (appPayload ? JSON.stringify(appPayload).length : 0)
  }

  updateVisibility() {
    this.hidden = this.payloads.length === 0
  }

  updateSpeedscopeLink() {
    const title = `${document.location.pathname.replaceAll('/', '_')}_${new Date().toISOString()}.stackprof.json`
    const speedscopeUrl = `${document.location.origin}${document.location.pathname}?flamegraph=1&flamegraph_interval=500&flamegraph_output=json&flamegraph_json`
    this.speedscopeLink.href = `/_speedscope/index.html#profileURL=${encodeURIComponent(
      speedscopeUrl,
    )}&title=${encodeURIComponent(title)}`
  }

  async toggleReactScan() {
    let url = window.location.href

    if (this.reactScanEnabled) {
      url = url.replace(/_reactscan=true/, '')
    } else {
      if (url.indexOf('?') > -1) {
        url += '&_reactscan=true'
      } else {
        url += '?_reactscan=true'
      }
    }

    window.location.href = url
  }

  setReactScanButtonAttributes() {
    if (this.reactScanEnabled) {
      // eslint-disable-next-line i18n-text/no-en
      this.enableReactScanButton!.textContent = 'Disable React Scan'
    } else {
      // eslint-disable-next-line i18n-text/no-en
      this.enableReactScanButton!.textContent = 'Enable React Scan'
    }
  }
}
