// List of interactive elements tags based on W3C spec
// https://www.w3.org/TR/2013/CR-html5-20130806/dom.html#interactive-content-0
const interactiveElementTags =
  'a, audio, button, details, embed, iframe, img, input, keygen, label, object, select, textarea, video'

export function hideInteractiveElements(element: HTMLElement | Element | null) {
  element?.setAttribute('aria-hidden', 'true')

  /**
   * Hides all interactive elements within a container by making them inaccessible to keyboard navigation
   * and screen readers.
   *
   * @param waitPeriod - Number of milliseconds to wait before attempting to hide elements. Defaults to 0.
   *                     This is useful for elements that are loaded asynchronously.ies.
   *
   * The function:
   * 1. Sets aria-hidden="true" on all child elements to hide them from screen readers
   * 2. Sets tabindex="-1" on all interactive elements to remove them from keyboard navigation
   * 3. If no interactive elements are found (which might happen if content is still loading),
   *    it will recursively call itself with an increased wait period
   *
   * Note: This recursive approach is a temporary solution until comments and annotations
   * can be properly batched in future updates. See related issues:
   * - https://github.com/github/pull-requests/issues/15201
   * - https://github.com/github/pull-requests/issues/15206
   * - https://github.com/github/pull-requests/issues/15210
   */
  function hideAllElements(waitPeriod = 0) {
    setTimeout(() => {
      const allChildElements = Array.from(element?.querySelectorAll('*') ?? [])
      const interactiveElements = Array.from(element?.querySelectorAll(interactiveElementTags) ?? [])
      if (interactiveElements.length === 0) {
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

/**
 * Makes interactive elements within a container accessible to keyboard navigation and screen readers.
 * This function reverses the effects of hideInteractiveElements.
 *
 * @param element - The container element whose interactive children should be made accessible
 *
 * The function:
 * 1. Sets aria-hidden="false" on the container element to make it visible to screen readers
 * 2. Sets aria-hidden="false" on all child elements to make them visible to screen readers
 * 3. Sets tabindex="0" on all interactive elements to restore keyboard navigation
 */
export function showInteractiveElements(element: HTMLElement | Element | null) {
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
