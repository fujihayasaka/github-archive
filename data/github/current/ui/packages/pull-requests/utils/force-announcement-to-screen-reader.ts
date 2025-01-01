import {ssrSafeDocument} from '@github-ui/ssr-utils'

function createScreenReaderAnnouncementDiv() {
  if (typeof ssrSafeDocument === 'undefined') return
  const dummyDiv = ssrSafeDocument.createElement('div')
  dummyDiv.classList.add('sr-only', 'mt-n1')
  dummyDiv.id = 'screenReaderAnnouncementDiv'
  dummyDiv.setAttribute('role', 'alert')
  dummyDiv.setAttribute('data-testid', 'screenReaderAnnouncement')
  dummyDiv.setAttribute('aria-live', 'assertive')
  ssrSafeDocument.body.appendChild(dummyDiv)
  return dummyDiv
}

export function forceAnnouncementToScreenReaders(textToAnnounce: string, timeoutBeforeAnnouncing = 0) {
  if (typeof ssrSafeDocument === 'undefined') return
  // doing 'or undefined' for type safety
  let screenReaderDiv = ssrSafeDocument.getElementById('screenReaderAnnouncementDiv') ?? undefined

  if (!screenReaderDiv) {
    screenReaderDiv = createScreenReaderAnnouncementDiv()
  }
  if (!screenReaderDiv) return //something went wrong creating the div

  const textToAnnounceDeDuped =
    screenReaderDiv.textContent === textToAnnounce ? `${textToAnnounce}\u00A0` : textToAnnounce

  setTimeout(() => {
    if (screenReaderDiv) {
      screenReaderDiv.textContent = textToAnnounceDeDuped
    }
  }, timeoutBeforeAnnouncing)
}
