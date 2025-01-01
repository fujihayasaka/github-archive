import {isFeatureEnabled} from '@github-ui/feature-flags'
import {ssrSafeDocument} from '@github-ui/ssr-utils'
/**
 * IMPORTANT NOTICE: Feature flags added here must also be added to the `lib/github/client_side_feature_flags.rb` file
 * or they will not be available to check in this file!
 */

class CopilotFeatureFlags {
  /**
   * Returns a boolean indicating whether the Copilot conversational UX embedding update feature is enabled.
   * @returns {boolean} Whether the feature is enabled.
   */
  public get embedding() {
    return isFeatureEnabled('copilot_conversational_ux_embedding_update')
  }

  public get unstickyReferences() {
    return isFeatureEnabled('copilot_conversational_ux_history_refs')
  }

  public get implicitContext() {
    return isFeatureEnabled('COPILOT_IMPLICIT_CONTEXT')
  }

  public get issueCreation() {
    return isFeatureEnabled('copilot_issue_creation')
  }

  public get staticThreadSuggestions() {
    return isFeatureEnabled('copilot_chat_static_thread_suggestions')
  }

  public get followUpThreadSuggestions() {
    return isFeatureEnabled('copilot_chat_follow_up_thread_suggestions')
  }

  public get customInstructions() {
    return isFeatureEnabled('copilot_chat_custom_instructions')
  }

  public get reactMarkdown() {
    return isFeatureEnabled('copilot_react_markdown')
  }

  public get dotcomUserServerTokens() {
    return isFeatureEnabled('copilot_chat_dotcom_user_server_tokens')
  }

  public get copilotImmersiveV1() {
    return ssrSafeDocument?.querySelector('react-app[app-name=copilot-immersive-v1]') !== null
  }

  public get immersiveFilePreview() {
    return this.copilotImmersiveV1 && isFeatureEnabled('copilot_immersive_file_preview')
  }

  public get magicKBs() {
    return isFeatureEnabled('copilot_chat_magic_kbs')
  }

  public get bringYourOwnKey() {
    return isFeatureEnabled('copilot_byok')
  }

  public get newReferencesUI() {
    return isFeatureEnabled('copilot_new_references_ui')
  }

  public get improvedCodeBlocks() {
    return isFeatureEnabled('copilot_chat_improved_code_blocks')
  }

  public get immersiveTitleFavicon() {
    return isFeatureEnabled('copilot_immersive_title_favicon')
  }

  public get repoCustomInstructions() {
    return isFeatureEnabled('copilot_chat_repo_custom_instructions')
  }
}

export const copilotFeatureFlags = new CopilotFeatureFlags()
export type {CopilotFeatureFlags}
