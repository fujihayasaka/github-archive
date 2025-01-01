import {generateAppId, registerAppId} from '@github-ui/app-uuid'
import {getQueryClient} from '@github-ui/react-core/query-client'
import ReactProfilingMode from '@github-ui/react-profiling-mode'
import type {DetailedHTMLProps, HTMLAttributes} from 'react'
import type {createRoot as createRootType, hydrateRoot as hydrateRootType, Root} from 'react-dom/client'
import {createRoot} from 'react-dom/client'

import Memex from './memex'
import {renderMemex} from './render-memex'
import {PROJECT_ROUTE} from './routes'

type ReactDOM = {
  createRoot: typeof createRootType
  hydrateRoot: typeof hydrateRootType
}

class ProjectsV2 extends HTMLElement {
  declare reactRoot: Root | undefined
  declare uuid: string

  async connectedCallback() {
    const createRootFromClientOrProfiling = ReactProfilingMode.isEnabled()
      ? (await this.#getReactDomWithProfiling()).createRoot
      : createRoot
    const reactRoot = createRootFromClientOrProfiling(this)
    this.reactRoot = reactRoot
    const match = PROJECT_ROUTE.matchFullPathOrChildPaths(window.location.pathname)
    if (!match) return

    this.uuid = generateAppId()
    registerAppId(this.uuid)
    renderMemex(<Memex rootElement={this} />, this, reactRoot)
  }

  disconnectedCallback() {
    getQueryClient().removeQueries({queryKey: ['memex']})
    this.reactRoot?.unmount()
  }

  #getReactDomWithProfiling() {
    return import('react-dom/profiling') as unknown as Promise<ReactDOM>
  }
}

function register() {
  if (typeof window === 'undefined') return
  if (!window.customElements.get('projects-v2')) {
    // eslint-disable-next-line wc/tag-name-matches-class
    window.customElements.define('projects-v2', ProjectsV2)
  }
}

declare global {
  namespace JSX {
    interface IntrinsicElements {
      'projects-v2': DetailedHTMLProps<HTMLAttributes<ProjectsV2>, ProjectsV2>
    }
  }
}

register()
