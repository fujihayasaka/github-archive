import { default as AutoCheckElement } from '@github/auto-check-element'
import { on } from 'delegated-events'

on('auto-check-start', 'auto-check input', (event) => {
  const input = event.currentTarget! as HTMLInputElement

  if (input.value) {
    input.setCustomValidity('Checking…')
    toggleCheck(input, false)
    toggleSpinner(input, true)
  } else {
    toggleMessage(input)
    toggleSpinner(input, false)
    toggleCheck(input, false)
  }
})

on('auto-check-success', 'auto-check input', (event) => {
  const input = event.currentTarget! as HTMLInputElement

  toggleMessage(input)
  toggleSpinner(input, false)
  toggleCheck(input, true)
})

on('auto-check-error', 'auto-check input', async (event) => {
  const input = event.currentTarget! as HTMLInputElement
  const { response } = event.detail
  const content = await response.text()

  toggleMessage(input, content)
  toggleSpinner(input, false)
  toggleCheck(input, false)
})

function toggleMessage(input: HTMLInputElement, content = '') {
  const autoCheck = input.closest('auto-check')! as AutoCheckElement
  const formGroup = autoCheck.querySelector('[data-form-group]') as HTMLElement
  const note = autoCheck.querySelector('[data-note]') as HTMLElement
  const message = autoCheck.querySelector('[data-message]') as HTMLElement

  input.setCustomValidity(content)

  if (formGroup) {
    formGroup.classList.toggle('errored', !!content)
  }

  if (note) {
    note.hidden = !content
  }

  if (message) {
    message.textContent = content
  }
}

function toggleSpinner(input: HTMLInputElement, active: boolean) {
  const autoCheck = input.closest('auto-check')! as AutoCheckElement
  const spinner = autoCheck.querySelector('[data-spinner]') as HTMLElement

  if (spinner) {
    spinner.toggleAttribute('hidden', !active)
  }
}

function toggleCheck(input: HTMLInputElement, active: boolean) {
  const autoCheck = input.closest('auto-check')! as AutoCheckElement
  const check = autoCheck.querySelector('[data-check]') as HTMLElement

  if (check) {
    check.toggleAttribute('hidden', !active)
  }
}
