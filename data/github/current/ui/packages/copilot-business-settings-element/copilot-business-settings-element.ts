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
    if (this.userFeedbackOptInCheckbox.getAttribute('data-checked') === 'false') {
      this.userFeedbackOptInForm.copilot_user_feedback_opt_in.value = 'enabled'
    } else {
      this.userFeedbackOptInForm.copilot_user_feedback_opt_in.value = 'disabled'
    }
    this.userFeedbackOptInForm.submit()
  }

  toggleBetaFeaturesOptIn() {
    if (this.betaFeaturesOptInCheckbox.getAttribute('data-checked') === 'false') {
      this.betaFeaturesOptInForm.copilot_beta_features_opt_in.value = 'enabled'
    } else {
      this.betaFeaturesOptInForm.copilot_beta_features_opt_in.value = 'disabled'
    }
    this.betaFeaturesOptInForm.submit()
  }
}
