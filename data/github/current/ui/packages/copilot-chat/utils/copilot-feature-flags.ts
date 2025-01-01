import {isFeatureEnabled} from '@github-ui/feature-flags'

/**
 * IMPORTANT NOTICE: Feature flags added here must also be added to the `lib/github/client_side_feature_flags.rb` file
 * or they will not be available to check in this file!
 */

class CopilotFeatureFlags {
  public get customInstructions() {
    return isFeatureEnabled('copilot_chat_custom_instructions')
  }

  public get immersiveFigmaIntegration() {
    return isFeatureEnabled('copilot_immersive_figma_integration')
  }

  public get immersiveIssuePreview() {
    return isFeatureEnabled('copilot_immersive_issue_preview')
  }

  public get draftIssueTemplateRequiredIfBlankIssuesDisabled() {
    return isFeatureEnabled('copilot_immersive_draft_issue_template_required')
  }

  public get draftIssueUI() {
    return !isFeatureEnabled('copilot_immersive_disable_draft_issue_ui')
  }

  public get draftIssueTree() {
    return isFeatureEnabled('copilot_immersive_draft_issue_tree')
  }

  public get forceLegacyChatDefaultModel() {
    return isFeatureEnabled('copilot_api_force_legacy_base_chat_model')
  }

  public get domPageContext() {
    return isFeatureEnabled('copilot_use_dom_page_context')
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

  public get attachMultipleImages() {
    return isFeatureEnabled('copilot_chat_attach_multiple_images')
  }

  public get wholeAreaDragDrop() {
    return isFeatureEnabled('copilot_chat_wholearea_dd')
  }

  public get customCopilots() {
    return isFeatureEnabled('copilot_custom_copilots')
  }

  public get immersiveStructuredModelPicker() {
    return isFeatureEnabled('copilot_immersive_structured_model_picker')
  }

  public get spacesStarters() {
    return isFeatureEnabled('copilot_spaces_starters')
  }

  public get customCopilotsFeaturePreview() {
    return isFeatureEnabled('copilot_custom_copilots_feature_preview')
  }

  public get customCopilotVisibility() {
    return isFeatureEnabled('copilot_custom_copilots_visibility')
  }

  public get customCopilotOrgOwned() {
    return isFeatureEnabled('copilot_custom_copilots_org_owned')
  }

  public get customCopilot128kWindow() {
    return isFeatureEnabled('custom_copilots_128k_window')
  }

  public get clientDOMSkills() {
    return isFeatureEnabled('copilot_client_dom_skills')
  }

  public get dotcomChatClientSideSkills() {
    return isFeatureEnabled('dotcom_chat_client_side_skills')
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

  public get workbenchVMAgentAttachments() {
    return isFeatureEnabled('copilot_workbench_vm_agent_attachments')
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

  public get copilotSharedForbiddenError() {
    return isFeatureEnabled('copilot_share_forbidden_error')
  }

  public get dotcomChatFileUpload() {
    return isFeatureEnabled('copilot_dotcom_chat_file_upload') && isFeatureEnabled('copilot_chat_attachments')
  }

  public get copilotChatO1Tools() {
    return isFeatureEnabled('copilot_api_tools_for_non_streaming_models')
  }

  public get topicsAsReferences() {
    return isFeatureEnabled('copilot_topics_as_references')
  }

  public get bingGroundingServiceEnabled() {
    return isFeatureEnabled('copilot_bing_search_use_azure_ai_agent_service')
  }

  public get bingGroundingUIEnabled() {
    // The new UI can only be enabled if the backend service is enabled
    return isFeatureEnabled('copilot_bing_search_use_grounding_ui') && this.bingGroundingServiceEnabled
  }

  public get showDeepCodeSearchButton() {
    return (
      isFeatureEnabled('copilot_show_deep_code_search_button') && isFeatureEnabled('copilot_api_search_agent_skill')
    )
  }

  /** If enabled, the top-level header button points towards immersive mode instead of opening assistive. */
  public get headerButtonToImmersive() {
    return isFeatureEnabled('copilot_header_button_to_immersive')
  }

  public get deleteAllConversations() {
    return isFeatureEnabled('copilot_delete_all_conversations')
  }

  public get staffPromptDialog() {
    return isFeatureEnabled('copilot_staff_prompt_dialog')
  }

  public get chatAutocomplete() {
    return isFeatureEnabled('copilot_chat_autocomplete')
  }

  public get workbenchTerminal() {
    return isFeatureEnabled('copilot_workbench_terminal')
  }

  public get workbenchPreviewAnalytics() {
    return isFeatureEnabled('copilot_workbench_preview_analytics')
  }

  public get workbenchRefreshOnWsod() {
    return isFeatureEnabled('copilot_workbench_refresh_on_wsod')
  }

  public get workbenchShowConnectionReloadBanner() {
    return isFeatureEnabled('copilot_workbench_connection_reload_banner')
  }

  public get pasteTextFiles() {
    return isFeatureEnabled('copilot_paste_text_files')
  }

  public get stableSubthreadingHelpers() {
    return isFeatureEnabled('copilot_stable_subthreading_helpers')
  }

  public get workbenchIteratePanel() {
    return isFeatureEnabled('copilot_workbench_iterate_panel')
  }

  public get visionAllowedInClaude() {
    return isFeatureEnabled('copilot_chat_vision_in_claude')
  }

  public get premiumRequestQuotasEnabled() {
    return isFeatureEnabled('copilot_premium_request_quotas')
  }

  public get freeToPaidTelemetry() {
    return isFeatureEnabled('copilot_free_to_paid_telem')
  }

  public get freeToPaidSettingsUpgrade() {
    return isFeatureEnabled('copilot_ftp_settings_upgrade')
  }

  public get workbenchUserLimits() {
    return isFeatureEnabled('copilot_workbench_user_limits')
  }

  public get singleUserIteration() {
    return isFeatureEnabled('copilot_spark_single_user_iteration')
  }

  public get freeToPaidYourCopilotSettings() {
    return isFeatureEnabled('copilot_ftp_your_copilot_settings')
  }

  public get freeToPaidUpgradeToProFromModels() {
    return isFeatureEnabled('copilot_ftp_upgrade_to_pro_from_models')
  }

  public get commitOnDefaultBranch() {
    return isFeatureEnabled('spark_commit_on_default_branch')
  }

  public get spacesIssuesPrsEnabled() {
    return isFeatureEnabled('custom_copilots_issues_prs')
  }

  public get customCopilotsFileUploads() {
    return isFeatureEnabled('custom_copilots_file_uploads')
  }

  public get copilotPersistEditedDraftIssues() {
    return isFeatureEnabled('copilot_immersive_draft_issue_persist_edited_issues_in_session')
  }

  public get sparkAuthTokenEndpoint() {
    return isFeatureEnabled('spark_auth_token_endpoint')
  }

  public get agentSessionsEnabled() {
    return isFeatureEnabled('copilot_immersive_agent_sessions')
  }

  public get updateUserEditStatus() {
    return isFeatureEnabled('spark_update_user_edit_status')
  }

  public get sparkUseStreaming() {
    return isFeatureEnabled('copilot_spark_use_streaming')
  }

  public get sparkUseBillingHeaders() {
    return isFeatureEnabled('copilot_spark_use_billing_headers')
  }

  public get newConversationStarters() {
    return isFeatureEnabled('copilot_new_conversation_starters')
  }

  public get workbenchDefaultSonnet4() {
    return isFeatureEnabled('workbench_default_sonnet4')
  }
}

export const copilotFeatureFlags = new CopilotFeatureFlags()
export type {CopilotFeatureFlags}
