import {target, controller} from '@github/catalyst'

@controller
export class CopilotBusinessSettingsElement extends HTMLElement {
  @target declare orgEnablementForm: HTMLFormElement
  @target declare submitButtonWithConfirmation: HTMLElement
  @target declare submitButtonWithoutConfirmation: HTMLElement
  @target declare bingGitHubChatForm: HTMLFormElement
  @target declare bingGitHubChatCheckbox: HTMLInputElement
  @target declare userFeedbackOptInForm: HTMLFormElement
  @target declare userFeedbackOptInCheckbox: HTMLInputElement
  @target declare betaFeaturesOptInForm: HTMLFormElement
  @target declare betaFeaturesOptInCheckbox: HTMLInputElement

  orgEnablementChanged() {
    const enablementValue = (
      this.orgEnablementForm.querySelector('input[name="copilot_enabled"]:checked') as HTMLInputElement
    )?.value

    if (enablementValue === 'disabled') {
      this.submitButtonWithConfirmation.hidden = false
      this.submitButtonWithoutConfirmation.hidden = true
    } else {
      this.submitButtonWithConfirmation.hidden = true
      this.submitButtonWithoutConfirmation.hidden = false
    }
  }

  toggleBingForGitHub() {
    this.bingGitHubChatForm.submit()
  }

  toggleUserFeedbackOptIn() {
    this.userFeedbackOptInForm.submit()
  }

  toggleBetaFeaturesOptIn() {
    this.betaFeaturesOptInForm.submit()
  }
}
