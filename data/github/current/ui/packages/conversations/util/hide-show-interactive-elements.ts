// List of interactive elements tags based on W3C spec
// https://www.w3.org/TR/2013/CR-html5-20130806/dom.html#interactive-content-0
const interactiveElementTags =
  'a, audio, button, details, embed, iframe, img, input, keygen, label, object, select, textarea, video'

export function hideInteractiveElements(element: HTMLElement | Element | null) {
  element?.setAttribute('aria-hidden', 'true')

  function hideAllElements(waitPeriod = 0) {
    setTimeout(() => {
      const allChildElements = Array.from(element?.querySelectorAll('*') ?? [])
      const interactiveElements = Array.from(element?.querySelectorAll(interactiveElementTags) ?? [])
      if (interactiveElements.length === 0) {
        // We currently fetching comments 1 at a time, plus making GraphQL queries.
        // We will be batching threads + comments and annotations in the future.
        // This timeout logic shouldn't be needed once these batching and GraphQL removal issues are completed:
        // https://github.com/github/pull-requests/issues/15201
        // https://github.com/github/pull-requests/issues/15206
        // https://github.com/github/pull-requests/issues/15210
        return hideAllElements(200)
      }

      for (const childElement of allChildElements) {
        childElement?.setAttribute('aria-hidden', 'true')
      }

      for (const interactiveElement of interactiveElements) {
        interactiveElement.setAttribute('tabindex', '-1')
      }
    }, waitPeriod)
  }
  hideAllElements()
}

export function showInteractiveElements(element: HTMLElement | Element | null) {
  const ariaShowWithTabIndex = () => {
    element?.setAttribute('aria-hidden', 'false')
    const allChildElements = Array.from(element?.querySelectorAll('*') ?? [])
    for (const childElement of allChildElements) {
      childElement?.setAttribute('aria-hidden', 'false')
    }

    const interactiveElements = Array.from(element?.querySelectorAll(interactiveElementTags) ?? [])
    for (const interactiveElement of interactiveElements) {
      interactiveElement.setAttribute('tabindex', '0')
    }
  }

  // We need to wait for the element to be rendered before we can set the aria-hidden attribute. The 100ms used here is a works 99% of the time solution, but it's nothing more than a stop-gap. We should be able to remove this once we move to TSQ and batch comment rendering.
  setTimeout(ariaShowWithTabIndex, 100)
}
