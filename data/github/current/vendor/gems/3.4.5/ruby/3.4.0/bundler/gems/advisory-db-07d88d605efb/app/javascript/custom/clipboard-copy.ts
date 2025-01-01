import { on } from 'delegated-events'

on('clipboard-copy', '[data-copy-feedback]', (event) => {
  const clipboardCopyElement = event.currentTarget
  const message = clipboardCopyElement.getAttribute('data-copy-feedback')!
  const originalLabel = clipboardCopyElement.getAttribute('aria-label')
  const direction =
    clipboardCopyElement.getAttribute('data-tooltip-direction') || 's'

  clipboardCopyElement.setAttribute('aria-label', message)
  clipboardCopyElement.classList.add('tooltipped', `tooltipped-${direction}`)
  if (!(clipboardCopyElement instanceof HTMLElement)) return

  setTimeout(() => {
    if (originalLabel) {
      clipboardCopyElement.setAttribute('aria-label', originalLabel)
    } else {
      clipboardCopyElement.removeAttribute('aria-label')
    }
    clipboardCopyElement.classList.remove(
      'tooltipped',
      `tooltipped-${direction}`,
    )
  }, 2000)
})
