import {attr, controller, target, targets} from '@github/catalyst'
import {ContextRegionCrumbElement} from './context-region-crumb-element'
import type {CrumbOptions} from '@github-ui/global-navigation/types'

@controller
export class ContextRegionElement extends HTMLElement {
  @attr isResponsive = false

  @target declare overflowMenuContainer: HTMLElement
  @targets declare crumbs: ContextRegionCrumbElement[]
  @targets declare overflowCrumbs: HTMLElement[]

  popCrumb() {
    this.removeCrumbElement(this.lastCrumb)
    this.crumbsChanged()
  }

  pushCrumb(crumb: CrumbOptions, notifyAboutChanges = true) {
    const currentCrumbIndex = this.crumbs.length
    const crumbElement = new ContextRegionCrumbElement()
    crumbElement.label = crumb.label

    if (crumb.href) {
      crumbElement.href = crumb.href
    }

    if (this.isResponsive) {
      crumbElement.isResponsive = true
    }

    if (this.isResponsive && currentCrumbIndex === 0) {
      // insert the first crumb before the overflow menu
      this.insertBefore(crumbElement, this.overflowMenuContainer)
    } else {
      this.appendChild(crumbElement)
    }

    if (notifyAboutChanges) {
      this.crumbsChanged()
    }
  }

  get crumbObjects(): CrumbOptions[] {
    return this.crumbs.map(crumb => {
      return {
        label: crumb.label,
        href: crumb.href,
        crumbId: crumb.crumbId,
      }
    }) as CrumbOptions[]
  }

  crumbsChanged() {
    this.dispatchEvent(
      new CustomEvent('context-region-changed', {
        detail: {crumbs: this.crumbObjects},
      }),
    )
  }

  replaceCrumbs(crumbs: CrumbOptions[]) {
    for (const crumb of this.crumbs) {
      this.removeCrumbElement(crumb)
    }

    for (const crumb of crumbs) {
      this.pushCrumb(crumb, false)
    }

    this.crumbsChanged()
  }

  replaceCurrentCrumb(crumb: CrumbOptions) {
    const lastCrumb = this.lastCrumb

    if (lastCrumb) {
      this.removeCrumbElement(lastCrumb)
      this.pushCrumb(crumb)
    }
  }

  renameCurrentCrumb(label: string) {
    const lastCrumb = this.lastCrumb

    if (lastCrumb) {
      lastCrumb.label = label
    }
  }

  get lastCrumb(): ContextRegionCrumbElement | undefined {
    return this.crumbs[this.crumbs.length - 1]
  }

  removeCrumbElement(crumb: ContextRegionCrumbElement | undefined) {
    if (crumb) {
      this.removeChild(crumb as Node)
    }
  }

  findOverflowCrumbById(crumbId: string) {
    return this.overflowCrumbs.find(crumb => crumb.getAttribute('data-crumb-id') === crumbId)
  }

  hideOverflowCrumb(crumbId: string) {
    const crumb = this.findOverflowCrumbById(crumbId)

    if (crumb) {
      crumb.setAttribute('hidden', 'true')
    }
  }

  showOverflowCrumb(crumbId: string) {
    const crumb = this.findOverflowCrumbById(crumbId)

    if (crumb) {
      crumb.removeAttribute('hidden')
    }
  }

  activateLastCrumbTooltip() {
    this.lastCrumb?.activateTooltip()
  }

  connectedCallback() {
    this.setAttribute('role', 'list')
  }
}
