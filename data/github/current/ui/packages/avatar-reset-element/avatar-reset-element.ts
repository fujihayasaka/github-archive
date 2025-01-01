import {attr, controller, target} from '@github/catalyst'

@controller
export class AvatarResetElement extends HTMLElement {
  @target declare removeButton: HTMLButtonElement

  @attr url = ''
  @attr gravatarEnabled = false
  @attr gravatarText = ''

  // Sets the text of the avatar reset button depending on whether or not the
  // user has a gravatar associated with their GitHub account.
  async connectedCallback() {
    if (!this.gravatarEnabled || this.gravatarText === '' || !this.removeButton) return

    const hasGravatar = await this.#fetchGravatarInfo()

    if (hasGravatar) {
      this.removeButton.textContent = this.gravatarText
    }
  }

  // Fetch the gravatarUrl, and check the `has_gravatar` property from the returning JSON.
  async #fetchGravatarInfo() {
    if (this.url === '') return false

    try {
      const response = await fetch(this.url, {headers: {Accept: 'application/json'}})
      if (!response.ok) return false
      const data = (await response.json()) as {has_gravatar: boolean}
      return data.has_gravatar
    } catch {
      return false
    }
  }
}
