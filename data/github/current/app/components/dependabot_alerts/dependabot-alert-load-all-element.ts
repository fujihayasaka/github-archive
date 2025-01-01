import {controller, target} from '@github/catalyst'

@controller
class DependabotAlertLoadAllElement extends HTMLElement {
  @target declare timelineEvents: HTMLElement
  @target declare paginationLoader: HTMLElement

  displayRemainingEvents() {
    this.timelineEvents.toggleAttribute('hidden')
    this.paginationLoader.toggleAttribute('hidden')
  }
}
