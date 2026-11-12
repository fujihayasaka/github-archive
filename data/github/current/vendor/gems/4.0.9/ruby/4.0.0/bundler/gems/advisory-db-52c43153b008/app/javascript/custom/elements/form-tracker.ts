import { controller, target, targets } from '@github/catalyst'

interface MaybeDisableableElement extends HTMLElement {
  disabled?: boolean
}

@controller
export class FormTrackerElement extends HTMLElement {
  initialSignature: string
  changed = false
  valid = false

  // Forms may dynamically add or remove form fields, changing the form's
  // values and form tracker's signature.
  formObserver: MutationObserver

  @target form: HTMLFormElement
  @targets disableWhenChanged: HTMLElement[]
  @targets disableWhenUnchanged: HTMLElement[]
  @targets disableWhenInvalid: HTMLElement[]

  connectedCallback() {
    this.formObserver = new MutationObserver(() => this.refresh())
    this.formObserver.observe(this.form, { subtree: true, childList: true })
    this.addEventListener('input', this.refresh)
    this.addEventListener('change', this.refresh)

    this.reset()
  }

  disconnectedCallback() {
    this.formObserver.disconnect()
    this.removeEventListener('input', this.refresh)
    this.removeEventListener('change', this.refresh)
  }

  /**
   * Check whether the form is changed or unchanged, and if the form has flipped
   * from one state to the other, re-render the form tracker's targeted
   * elements.
   */
  refresh() {
    const changed = formSignature(this.form) !== this.initialSignature
    const valid = this.form.checkValidity()

    if (changed !== this.changed || valid !== this.valid) {
      this.changed = changed
      this.valid = valid
      this.render()
    }
  }

  /**
   * Update the form tracker's targeted elements by either enabling or disabling
   * each based on whether the form is changed/unchanged or valid/invalid.
   */
  render() {
    const elementsToDisable = new Set()

    for (const element of this.disableWhenChanged) {
      setDisabledAttribute(element, false)

      if (this.changed) {
        elementsToDisable.add(element)
      }
    }

    for (const element of this.disableWhenUnchanged) {
      setDisabledAttribute(element, false)

      if (!this.changed) {
        elementsToDisable.add(element)
      }
    }

    for (const element of this.disableWhenInvalid) {
      setDisabledAttribute(element, false)

      if (!this.valid) {
        elementsToDisable.add(element)
      }
    }

    for (const element of elementsToDisable.values()) {
      setDisabledAttribute(element as MaybeDisableableElement, true)
    }
  }

  /**
   * Reset the initial form signature and re-render the form tracker's targeted
   * elements. This is wrapped in its own method so it can be used as a callback
   * in response to events dispatched by elements outside of this one.
   */
  reset() {
    this.initialSignature = formSignature(this.form)
    this.changed = false
    this.valid = this.form.checkValidity()

    this.render()
  }
}

/**
 * Get a signature that changes if the form is changed in any way that would
 * affect its submitted values.
 *
 * @param form - the content we want uniquely serialized
 *
 * @return A representation of the current state of the form's values
 */
function formSignature(form: HTMLFormElement): string {
  const formData = new FormData(form)
  const csrfParam = (
    document.querySelector('meta[name=csrf-param]') as HTMLMetaElement
  )?.content

  // Ignore the authenticity token since Rails' deferred setting of its value
  // introduces a race condition. The value doesn't change once set anyway.
  if (csrfParam) {
    formData.delete(csrfParam)
  }

  return JSON.stringify(Array.from(formData.entries()))
}

/**
 * Enable or disable an element, using either the disabled or aria-disabled
 * attribute, depending on which attribute the element supports.
 */
function setDisabledAttribute(
  element: MaybeDisableableElement,
  disabled: boolean,
) {
  if ('disabled' in element) {
    element.disabled = disabled
  } else {
    element.setAttribute('aria-disabled', disabled.toString())
  }
}
