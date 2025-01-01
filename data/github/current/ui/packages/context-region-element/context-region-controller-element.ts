import {attr, controller, target} from '@github/catalyst'
import type {CrumbOptions} from '@github-ui/global-navigation/types'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {debounce} from '@github/mini-throttle/decorators'
import {getBaseFetchHeaders} from '@github-ui/fetch-headers'
import type {ContextRegionElement} from './context-region-element'
import type {ContextRegionCrumbElement} from './context-region-crumb-element'
import type {ActionMenuElement} from '@primer/view-components/app/components/primer/alpha/action_menu/action_menu_element'

@controller
export class ContextRegionControllerElement extends HTMLElement {
  @attr isResponsive = false
  @attr maxItems: number = 5

  @target declare compactContainer: HTMLElement
  @target declare compactContextRegion: HTMLElement
  @target declare overflowMenuContainer: HTMLElement
  @target declare contextRegion: ContextRegionElement
  @target declare overflowActionMenu: ActionMenuElement

  // we cache arrays of the crumb IDs and their visibility state to avoid too many DOM operations,
  // when we usually just need a count of the elements in each group
  visibleCrumbIds: string[] = []
  overflowCrumbIds: string[] = []
  resizeObserver: ResizeObserver | null = null

  crumbsChanged(e: CustomEvent) {
    if (this.isResponsive) {
      this.setupResponsive()
      this.calculateVisibleCrumbs()
      this.fetchOverflowMenu(e.detail.crumbs)
    } else {
      this.fetchLegacyMobileContextRegion(e.detail.crumbs)
    }
  }

  // the overflow menu is rendered using an ActionMenu ViewComponent,
  // so we need to ask the server for a new version instead of trying to updated the items client-side
  @debounce(250)
  async fetchOverflowMenu(crumbs: CrumbOptions[]) {
    const route = '/_context-region/overflow'
    const formData = new FormData()

    formData.append('crumbs', JSON.stringify(crumbs))

    try {
      const response = await verifiedFetch(route, {
        method: 'POST',
        body: formData,
        headers: {
          Accept: 'text/html',
          ...getBaseFetchHeaders(),
        },
      })

      if (response.ok) {
        const html = await response.text()
        this.overflowMenuContainer.innerHTML = html
        this.syncOverflowCrumbs()
      }
    } catch {
      // Ignore network errors
    }
  }

  @debounce(250)
  fetchLegacyMobileContextRegion(crumbs: CrumbOptions[]) {
    // only make the request if the user can actually see the compact context region
    // (and if we're not in responsive mode)
    if (!this.isResponsive && this.compactContextRegion?.checkVisibility()) {
      this.fetchCompactContextRegion(crumbs)
    }
  }

  // this sends a post request to the server to get a new compact context region
  async fetchCompactContextRegion(crumbs: CrumbOptions[]) {
    const route = '/_context-region/compact'
    const formData = new FormData()

    formData.append('crumbs', JSON.stringify(crumbs))

    try {
      const response = await verifiedFetch(route, {
        method: 'POST',
        body: formData,
        headers: {
          Accept: 'text/html',
          ...getBaseFetchHeaders(),
        },
      })

      if (response.ok) {
        const html = await response.text()
        this.compactContainer.innerHTML = html
      }
    } catch {
      // Ignore network errors
    }
  }

  @debounce(50)
  handleResize() {
    this.calculateVisibleCrumbs()
  }

  setupResponsive() {
    this.visibleCrumbIds = []
    this.overflowCrumbIds = []

    // get the initial state of visible and hidden crumbs from the server-rendered context region
    for (const crumbElement of this.crumbElements) {
      if (crumbElement.hasAttribute('hidden')) {
        this.overflowCrumbIds.push(crumbElement.crumbId)
      } else {
        this.visibleCrumbIds.push(crumbElement.crumbId)
      }
    }

    this.syncOverflowCrumbs()
  }

  calculateVisibleCrumbs() {
    if (!this.crumbElements || this.totalItemLength <= 1) {
      return
    }

    requestAnimationFrame(() => {
      if (this.needToHideAnotherCrumb) {
        this.recursivelyHideNextCrumbs()
      } else if (this.hasRoomForAnotherCrumb && !this.anotherCrumbWouldExceedLimit) {
        this.recursivelyShowNextCrumbs()
      }

      // if there are any crumbs that are currently overflowing, we need to reveal the overflow menu
      this.overflowMenuContainer.toggleAttribute('hidden', this.overflowCrumbIds.length === 0)
      this.contextRegion?.activateLastCrumbTooltip()
    })
  }

  syncOverflowCrumbs() {
    for (const overflowCrumbId of this.overflowCrumbIds) {
      this.contextRegion.showOverflowCrumb(overflowCrumbId)
    }

    for (const visibleCrumbId of this.visibleCrumbIds) {
      this.contextRegion.hideOverflowCrumb(visibleCrumbId)
    }
  }

  recursivelyShowNextCrumbs() {
    const nextCrumb = this.nextCrumbToBeShown

    if (nextCrumb) {
      // let's make sure to preserve focus if the user is currently focused on the overflow crumb
      const overflowCrumb = this.contextRegion.findOverflowCrumbById(nextCrumb.crumbId)
      const overflowCrumbLinkElement = overflowCrumb?.querySelector('a')
      const mainCrumbLinkElement = nextCrumb.linkElement
      const shouldRestoreFocus = overflowCrumbLinkElement && document.activeElement === overflowCrumbLinkElement

      nextCrumb.removeAttribute('hidden')

      // update crumb ID caches
      this.visibleCrumbIds.push(nextCrumb.crumbId)
      this.overflowCrumbIds = this.overflowCrumbIds.filter(crumbId => crumbId !== nextCrumb.crumbId)

      // hide the corresponding overflow crumb when the primary crumb has been shown
      this.contextRegion.hideOverflowCrumb(nextCrumb.crumbId)

      // Restore focus and close popover if needed
      if (shouldRestoreFocus && mainCrumbLinkElement) {
        mainCrumbLinkElement.focus()
        this.overflowActionMenu.popoverElement?.hidePopover?.()
      }

      // if there's still more room, we can recursively continue adding crumbs
      if (this.hasRoomForAnotherCrumb && !this.anotherCrumbWouldExceedLimit && this.nextCrumbToBeShown) {
        this.recursivelyShowNextCrumbs()
      }
    }
  }

  recursivelyHideNextCrumbs() {
    const nextCrumb = this.nextCrumbToBeHidden

    if (nextCrumb) {
      const shouldRestoreFocus = nextCrumb.linkElement === document.activeElement

      nextCrumb.setAttribute('hidden', 'true')

      // update crumb ID caches
      this.overflowCrumbIds.push(nextCrumb.crumbId)
      this.visibleCrumbIds = this.visibleCrumbIds.filter(crumbId => crumbId !== nextCrumb.crumbId)

      // reveal the corresponding overflow crumb when the primary crumb has been hidden
      this.contextRegion.showOverflowCrumb(nextCrumb.crumbId)

      if (shouldRestoreFocus) {
        const overflowCrumb = this.contextRegion.findOverflowCrumbById(nextCrumb.crumbId)
        const overflowCrumbLinkElement = overflowCrumb?.querySelector('a')

        if (overflowCrumbLinkElement) {
          this.overflowActionMenu.popoverElement?.showPopover()

          const popoverElement = this.overflowActionMenu.popoverElement

          const focusHandler = () => {
            if (popoverElement?.contains(overflowCrumbLinkElement)) {
              overflowCrumbLinkElement.focus()
              popoverElement.removeEventListener('focusin', focusHandler)
            }
          }

          popoverElement?.addEventListener('focusin', focusHandler)
        }
      }

      if (this.nextCrumbToBeHidden && this.needToHideAnotherCrumb) {
        this.recursivelyHideNextCrumbs()
      }
    }
  }

  get needToHideAnotherCrumb(): boolean {
    const totalCrumbsOverLimit = this.totalItemLength > this.maxItems
    const needToHideDueToLimit = totalCrumbsOverLimit && this.visibleCount > this.maxItems - 1
    const needToHideBecauseLastCrumbIsOverflowing = this.contextRegion.lastCrumb?.isOverflowing() ?? false

    return needToHideDueToLimit || needToHideBecauseLastCrumbIsOverflowing
  }

  get crumbElements(): ContextRegionCrumbElement[] {
    return this.contextRegion.crumbs
  }

  get totalItemLength(): number {
    return this.visibleCrumbIds.length + this.overflowCrumbIds.length
  }

  get visibleCount(): number {
    return this.visibleCrumbIds.length
  }

  get overflowCount(): number {
    return this.overflowCrumbIds.length
  }

  get visibleCrumbs(): ContextRegionCrumbElement[] {
    return this.crumbElements.filter(crumbElement => !crumbElement.hasAttribute('hidden'))
  }

  get currentWidth(): number {
    const widthOfVisibleCrumbs = this.visibleCrumbs.reduce((total, crumbElement) => {
      return total + crumbElement.getBoundingClientRect().width
    }, 0)

    return widthOfVisibleCrumbs + this.overflowMenuWidth
  }

  get overflowMenuWidth(): number {
    return this.overflowMenuContainer.getBoundingClientRect().width
  }

  get nextCrumbToBeHidden(): ContextRegionCrumbElement | undefined {
    const visibleCrumbs = this.visibleCrumbs

    // return the crumb immediately after the overflow menu. never return the last crumb.
    const lastCrumb = visibleCrumbs[this.visibleCount - 1]

    if (!lastCrumb || visibleCrumbs.indexOf(lastCrumb) === 0) {
      return undefined
    }

    // if we've already hidden all but the first and last crumb, it's time to hide the first crumb
    if (this.overflowCount === this.totalItemLength - 2) {
      return visibleCrumbs[0]
    }

    return visibleCrumbs[1]
  }

  get nextCrumbToBeShown(): ContextRegionCrumbElement | undefined {
    const crumbElements = this.crumbElements

    if (crumbElements[0]?.hasAttribute('hidden')) {
      // if the first crumb is hidden, that's the next one to show
      return crumbElements[0]
    }

    const hiddenCrumbs = crumbElements.filter(crumbElement => crumbElement.hasAttribute('hidden'))
    // otherwise, the bottom crumb in the overflow menu is the next one to show
    return hiddenCrumbs[this.overflowCount - 1]
  }

  get hasRoomForAnotherCrumb(): boolean {
    const nextCrumb = this.nextCrumbToBeShown

    if (nextCrumb) {
      return this.currentWidth + nextCrumb.potentialWidth <= this.getBoundingClientRect().width
    }

    return false
  }

  get anotherCrumbWouldExceedLimit(): boolean {
    let limit = this.maxItems

    // if the overflow menu is visible, we need to offset the limit by one
    if (this.overflowMenuContainer.checkVisibility()) {
      limit -= 1
    }

    return this.visibleCount + 1 > limit
  }

  connectedCallback() {
    if (this.isResponsive) {
      this.setupResponsive()

      this.resizeObserver = new ResizeObserver(entries => {
        if (entries.length === 0) {
          return
        }

        this.handleResize()
      })

      this.resizeObserver.observe(document.body)
      this.dispatchEvent(new CustomEvent('context-region-connected'))
    }
  }

  disconnectedCallback() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    }
  }
}
