import {attr, controller, target, targets} from '@github/catalyst'

@controller
class LaunchCodeElement extends HTMLElement {
  @target declare form: HTMLFormElement
  @targets declare inputs: HTMLInputElement[]
  @target declare result: HTMLElement
  @attr declare pattern: string

  connectedCallback() {
    this.handleLoaded()
  }

  handlePaste(event: ClipboardEvent) {
    event.preventDefault()
    const clipboardData = event.clipboardData

    if (!clipboardData) return

    const launchCode = clipboardData.getData('text')

    const launchCodeRegExp = new RegExp(`^${this.pattern}*$`)
    if (!launchCodeRegExp.test(launchCode)) return

    let lastInputElement

    for (const inputField of this.inputs) {
      const thisInputIndex = this.inputs.indexOf(inputField)
      lastInputElement = inputField
      if (!launchCode[thisInputIndex]) break
      inputField.value = launchCode[thisInputIndex]!
    }

    if (this.form.checkValidity()) {
      this.form.submit()
    } else {
      lastInputElement?.focus()
    }
  }

  handleKeyInput(event: Event) {
    const input = event.target as HTMLInputElement
    const thisInputIndex = this.inputs.indexOf(input)
    const nextInput = this.inputs[thisInputIndex + 1]

    if (this.result.innerHTML.trim() !== '') {
      // If we were displaying an error but the user
      // is now entering a new code, clear the current
      // error message.
      this.result.textContent = ''
    }

    if (input.checkValidity()) {
      if (nextInput) {
        if (this.form.checkValidity()) {
          this.form.submit()
        } else {
          nextInput.focus()
        }
      } else {
        if (this.form.reportValidity()) this.form.submit()
      }
    } else {
      input.value = ''
    }
  }

  handleKeyNavigation(event: KeyboardEvent) {
    // TODO: Refactor to use data-hotkey
    /* eslint eslint-comments/no-use: off */
    /* eslint-disable @github-ui/ui-commands/no-manual-shortcut-logic */
    const navigationKeys = ['Backspace', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown']
    if (!navigationKeys.includes(event.key)) return

    const input = event.target as HTMLInputElement
    const thisInputIndex = this.inputs.indexOf(input)
    const nextInput = this.inputs[thisInputIndex + 1]

    switch (event.key) {
      case 'Backspace': {
        const previousInput = this.inputs[thisInputIndex - 1]
        if (previousInput) {
          previousInput.focus()
          previousInput.value = ''
          this.result.textContent = ''
        }
        return
      }
      case 'ArrowLeft': {
        const previousInput = this.inputs[thisInputIndex - 1]
        if (previousInput) previousInput.focus()
        return
      }
      case 'ArrowRight': {
        if (nextInput) nextInput.focus()
        return
      }
      case 'ArrowUp':
      case 'ArrowDown': {
        event.preventDefault()
        return
      }
    }
    /* eslint-enable @github-ui/ui-commands/no-manual-shortcut-logic */
  }

  handleLoaded() {
    if (this.result.innerHTML.trim() !== '') {
      this.forceResultScreenReaderAnnounce()
    }
  }

  private forceResultScreenReaderAnnounce() {
    // This is a hack to force the screen reader to read out the message.
    // See https://github.com/github/accessibility/issues/290 where we do
    // something similar for our flash messages.
    setTimeout(() => {
      if (this.result.firstElementChild) {
        this.result.firstElementChild.appendChild(document.createTextNode('\u00a0'))
      }
    }, 200)
  }
}
