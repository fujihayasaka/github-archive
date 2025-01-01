import {isFeatureEnabled} from '@github-ui/feature-flags'

/**
 * IMPORTANT NOTICE: Feature flags added here must also be added to the `lib/github/client_side_feature_flags.rb` file
 * or they will not be available to check in this file!
 */

class CopilotFeatureFlags {
  public get unstickyReferences() {
    return isFeatureEnabled('copilot_conversational_ux_history_refs')
  }

  public get customInstructions() {
    return isFeatureEnabled('copilot_chat_custom_instructions')
  }

  public get immersiveFigmaIntegration() {
    return isFeatureEnabled('copilot_immersive_figma_integration')
  }

  public get immersiveIssuePreview() {
    return isFeatureEnabled('copilot_immersive_issue_preview')
  }

  /**
   * Aggregates feature flags that require the service navigation UX. If any of these flags are enabled,
   * the service navigation will be displayed.
   */
  public get immersiveServiceNavigation() {
    return this.customCopilots || this.pipesPlugin || this.workbenchPlugin
  }

  /**
   * When enabled, the interview survey dialog replaces the 'Give feedback' dialog in copilot chat.
   * @returns {boolean} Whether the feature is enabled.
   */
  public get copilotChatInterviewSurvey() {
    return isFeatureEnabled('copilot_chat_interview_survey')
  }

  public get newImmersiveReferencesUI() {
    return isFeatureEnabled('copilot_new_immersive_references_ui')
  }

  public get repoCustomInstructions() {
    return isFeatureEnabled('copilot_chat_repo_custom_instructions')
  }

  public get repoCustomInstructionsPreview() {
    return isFeatureEnabled('copilot_chat_repo_custom_instructions_preview')
  }

  public get attachImagesImmersive() {
    return isFeatureEnabled('copilot_chat_attach_images')
  }

  public get immersiveSubthreading() {
    return isFeatureEnabled('copilot_chat_immersive_subthreading')
  }

  public get retryModelPicker() {
    return isFeatureEnabled('copilot_chat_show_model_picker_on_retry')
  }

  public get customCopilots() {
    return isFeatureEnabled('copilot_custom_copilots')
  }

  /**
   * Temporary flag to enable the file picker for spaces editor.
   */
  public get shareConversation() {
    return isFeatureEnabled('copilot_share_conversation')
  }

  public get clientDOMSkills() {
    return isFeatureEnabled('copilot_client_dom_skills')
  }

  public get dotcomChatClientSideSkills() {
    return isFeatureEnabled('dotcom_chat_client_side_skills')
  }

  public get ambientErrorBanner() {
    return isFeatureEnabled('copilot_chat_ambient_error_banner')
  }

  public get taskOrientedAssistive() {
    return isFeatureEnabled('copilot_task_oriented_assistive')
  }

  public get pipesPlugin() {
    return isFeatureEnabled('copilot_pipes')
  }

  public get workbenchPlugin() {
    return isFeatureEnabled('copilot_workbench')
  }

  public get copilotChatOpeningThreadSwitch() {
    return isFeatureEnabled('copilot_chat_opening_thread_switch')
  }

  public get copilotReadSharedConversation() {
    return isFeatureEnabled('copilot_read_shared_conversation')
  }

  public get copilotDuplicateThread() {
    return isFeatureEnabled('copilot_duplicate_thread')
  }

  public get copilotShareActiveSubthread() {
    return isFeatureEnabled('copilot_share_active_subthread')
  }

  public get copilotUIRefs() {
    return isFeatureEnabled('copilot_ui_refs')
  }

  public get dotcomChatFileUpload() {
    return isFeatureEnabled('copilot_dotcom_chat_file_upload')
  }

  public get bufferStreamingContent() {
    return isFeatureEnabled('copilot_buffered_streaming')
  }

  public get copilotChatO1Tools() {
    return isFeatureEnabled('copilot_api_tools_for_non_streaming_models')
  }

  public get topicsAsReferences() {
    return isFeatureEnabled('copilot_topics_as_references')
  }
}

export const copilotFeatureFlags = new CopilotFeatureFlags()
export type {CopilotFeatureFlags}
