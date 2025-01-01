import {controller, target} from '@github/catalyst'
import {type Root, createRoot} from 'react-dom/client'

import {renderStaffBarReactQueryDevToolsPanel} from './TanstackQueryDevtools/RenderStaffbarReactQueryDevtoolsPanel'
import {getIsQueryPanelOpen, setIsQueryPanelOpen} from './TanstackQueryDevtools/session-store'

@controller
class ReactQueryDevtoolsElement extends HTMLElement {
  @target declare panelRootElement: HTMLDivElement
  @target declare toggleDevtoolsVisibilityButton: HTMLButtonElement
  declare panelRoot: Root

  connectedCallback() {
    this.panelRoot = createRoot(this.panelRootElement)
    renderStaffBarReactQueryDevToolsPanel(this.panelRoot, {
      toggleDevtoolsVisibilityButton: this.toggleDevtoolsVisibilityButton,
      handleDevtoolsVisibilityChange: this.#handleDevtoolsVisibilityChange,
    })
  }

  disconnectedCallback() {
    this.panelRoot.unmount()
  }

  #handleDevtoolsVisibilityChange(next?: boolean) {
    const nextIsOpen = next ?? !getIsQueryPanelOpen()
    setIsQueryPanelOpen(nextIsOpen)
  }

  toggleDevtoolsVisibility() {
    this.#handleDevtoolsVisibilityChange()
  }
}
