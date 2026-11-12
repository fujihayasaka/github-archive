import { on } from 'delegated-events'

on('click', '[data-set-color-mode]', async (event) => {
  const selectedButton = event.currentTarget as HTMLButtonElement
  const mode = selectedButton.getAttribute('data-set-color-mode')!
  document.body.setAttribute('data-color-mode', mode)

  for (const button of document.querySelectorAll('[data-set-color-mode')!) {
    button.setAttribute('aria-checked', 'false')
  }
  selectedButton.setAttribute('aria-checked', 'true')
})
