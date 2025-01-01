// eslint-disable-next-line filenames/match-regex
import {createBrowserHistory} from '@github-ui/react-core/create-browser-history'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import type {History} from '@remix-run/router'
import {type Root, createRoot} from 'react-dom/client'
import {renderCreateDialogPartialEntry} from './IssueCreateDialogWebComponent'

export class IssueCreateDialogElement extends HTMLElement {
  root: Root | undefined
  history?: History

  connectedCallback() {
    const container = document.createElement('div')
    this.history = createBrowserHistory({window})

    this.root = createRoot(container)
    this.append(container)
    this.render()
  }

  disconnectedCallback() {
    this.root?.unmount()
  }

  static get observedAttributes() {
    return ['isenabled', 'key', 'owner', 'repository', 'analytics-app-name', 'analytics-namespace']
  }

  attributeChangedCallback() {
    if (!this.isConnected) return
    this.render()
  }

  render() {
    const isEnabled = this.getAttribute('isenabled') === 'true'
    const key = this.getAttribute('key') ?? undefined
    const owner = this.getAttribute('owner') ?? undefined
    const repository = this.getAttribute('repository') ?? undefined
    const analyticsAppName = this.getAttribute('analytics-app-name') ?? undefined
    const analyticsNamespace = this.getAttribute('analytics-namespace') ?? undefined
    if (!this.root || !isEnabled || !key || key.length < 1 || !this.history) return

    renderCreateDialogPartialEntry(this.root, {
      key,
      history: this.history,
      owner,
      repository,
      analyticsAppName,
      analyticsNamespace,
    })
  }
}

if (ssrSafeWindow && !ssrSafeWindow.customElements.get('issue-create-dialog')) {
  ssrSafeWindow.customElements.define('issue-create-dialog', IssueCreateDialogElement)
}
