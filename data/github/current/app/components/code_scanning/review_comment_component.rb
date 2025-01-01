# typed: true
# frozen_string_literal: true

class CodeScanning::ReviewCommentComponent < ApplicationComponent
  include CodeScanningHelper

  AlertDetails = T.type_alias { CodeQualityPullRequestFinding::AlertDetails }
  SuggestedFix = T.type_alias { T.any(CodeQualityPullRequestFinding::SuggestedFix, Turboscan::Proto::SuggestedFix) }
  SuggestedFixAlert = T.type_alias { T.any(CodeQualityPullRequestFinding::SuggestedFixAlert, Turboscan::Proto::SuggestedFixAlert) }

  FEEDBACK_LABELS = {
    CODE_SCANNING_AUTOFIX_FEEDBACK_ALERT_NOT_RELEVANT: "The alert is not relevant, and no fix is needed",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_HAS_ERRORS: "The fix is partially correct, but has errors",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_IS_UNHELPFUL: "The fix is not helpful at all",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WONT_ADDRESS_PROBLEM: "Unsure if this fix will address the security vulnerability",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WILL_BREAK_FUNCTIONALITY: "Unsure if this fix will break code functionality",
    CODE_SCANNING_AUTOFIX_FEEDBACK_OTHER: "Other reason"
  }

  FEEDBACK_LABELS_CODE_QUALITY = FEEDBACK_LABELS.merge({
    CODE_SCANNING_AUTOFIX_FEEDBACK_ALERT_NOT_RELEVANT: "The finding is not relevant, and no fix is needed"
  })

  def self.preload_review_comment(pull_request:, pull_request_review_comment:)
    code_scanning_review_comment = pull_request.code_scanning_review_comment_for_comment(pull_request_review_comment.id)
    alert_numbers = code_scanning_review_comment ? [code_scanning_review_comment.alert_number] : []
    pull_request.override_code_scanning_alert_numbers!(alert_numbers)
    preload_review_comments(pull_request:)
  end

  def self.preload_review_comments(pull_request:)
    pull_request.async_preload_code_scanning_alerts
    pull_request.async_preload_code_scanning_suggested_fixes
    pull_request.code_scanning_review_comments
  end

  attr_reader :pull_request_review_comment, :pull_request, :autofix_header_type, :skip_interactive_elements, :skip_view_patch_menu_item

  def initialize(
    pull_request_review_comment:,
    pull_request:,
    autofix_header_type: :default,
    comment_context: nil,
    skip_interactive_elements: false,
    skip_view_patch_menu_item: false,
    code_quality: false
  )
    @autofix_header_type = autofix_header_type
    @pull_request_review_comment = pull_request_review_comment
    @pull_request = pull_request
    @skip_interactive_elements = skip_interactive_elements
    @skip_view_patch_menu_item = skip_view_patch_menu_item
    @code_quality = code_quality
  end

  sig { returns(T::Boolean) }
  def code_quality?
    @code_quality
  end

  sig { returns(T.nilable(CodeQualityPullRequestFinding)) }
  memoize def code_quality_finding
    return nil unless code_quality?

    pull_request.code_quality_finding_for_review_comment(@pull_request_review_comment.id)
  end

  sig { returns(AlertDetails) }
  memoize def alert_details
    if code_quality?
      code_quality_finding
    else
      pull_request.code_scanning_review_comment_for_comment(@pull_request_review_comment.id)
    end
  end

  def fallback_alert_title
    alert_details.alert_title
  end

  def fallback_alert_message
    alert_details.alert_message
  end

  def fallback_warning_level
    alert_details.warning_level
  end

  def fallback_tool_name
    alert_details.tool_name
  end

  sig { returns(T.nilable(Integer)) }
  def alert_number
    alert_details.alert_number
  end

  # Returns the alert number for code scanning.
  # This should only be called in the context of displaying a code scanning alert.
  sig { returns(Integer) }
  def turboscan_alert_number
    T.must(alert_number)
  end

  # sig { returns(T.nilable(T.any(Turboscan::Proto::AnnotationResult, Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::AnnotationResult))) }
  memoize def annotation_result
    if code_quality?
      code_quality_finding&.annotation_result
    else
      pull_request.code_scanning_alert_for_review_comment(@pull_request_review_comment)
    end
  end

  memoize def pull_request_refs
    pull_request.code_scanning_latest_check_suite&.refs
  end

  memoize def commit_suggestion_modal_id
    "commit-suggested-fix-modal-#{pull_request_review_comment.id}"
  end

  memoize def author
    pull_request_review_comment.async_user.then do |user|
      next User.ghost if user.nil? || user.hide_from_user?(current_user)

      user
    end.sync
  end

  memoize def thread
    pull_request_review_comment.pull_request_review_thread
  end

  memoize def repository
    pull_request&.repository || current_repository
  end

  memoize def current_head_oid
    with_database_error_fallback do
      pull_request.current_head_oid
    end
  end

  sig { returns T.nilable(SuggestedFixAlert) }
  memoize def suggested_fix_alert
    if code_quality?
      code_quality_finding&.suggested_fix_alert
    else
      pull_request.code_scanning_suggested_fix_alert(turboscan_alert_number)
    end
  end

  def suggested_fix_alert?
    suggested_fix_alert.present?
  end

  def suggested_fix_alert_pending?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_PENDING
  end

  def suggested_fix_alert_error?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_ERROR
  end

  memoize def suggested_fix
    suggested_fix_alert&.suggested_fix
  end

  memoize def show_suggested_fix?
    return false unless autofix_enabled?
    return false unless suggested_fix? # Don't show the suggested fix if there isn't one
    return false if invalid_suggested_fix? # Don't show the suggested fix if it is invalid

    true
  end

  memoize def show_suggested_fix_actions?
    return false if @skip_interactive_elements
    return false if applied_suggested_fix?
    return false if outdated_suggested_fix?
    return false if code_scanning_alert_resolved?

    pull_request.can_apply_code_scanning_suggested_fix?(current_user)
  end

  def hide_suggested_fix_summary?
    !collapse_suggested_fix? # Only show the summary if the suggested fix is collapsed
  end

  def collapse_suggested_fix?
    applied_suggested_fix?
  end

  def collapsed_suggested_fix_message
    if applied_suggested_fix?
      "This autofix suggestion was applied."
    end
  end

  memoize def suggested_fix_description
    GitHub::Goomba::MarkdownPipeline.to_html(suggested_fix&.description)
  end

  memoize def suggested_fix_diff_entries
    CodeScanning::AutofixSuggestion.new(suggested_fix).diff_entries
  end

  memoize def suggested_fix_file_highlighting
    suggested_fix_diff_entries.each_with_object({}) do |diff_entry, out|
      out[diff_entry.path] = DiffEntryHighlighting.new(diff_entry).highlight_lines
    end
  end

  def suggested_fix_dependency_metadata
    suggested_fix.dependency_metadata
  end

  def annotation_wrapper(&block)
    yield
    nil # Returning `yield` causes a double render
  end

  def suggested_fix?
    suggested_fix.present? && suggested_fix_diff_entries.any?
  end

  memoize def applied_suggested_fix?
    return false unless suggested_fix?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_APPLIED
  end

  def invalid_suggested_fix?
    return false unless suggested_fix_alert?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_INVALID
  end

  def outdated_suggested_fix?
    return false unless suggested_fix?
    if code_quality_finding.present?
      code_quality_finding&.commit_oid != current_head_oid
    else
      suggested_fix.outdated
    end
  end

  sig { returns(T.nilable(User)) }
  memoize def state_updated_by
    if suggested_fix_alert&.state_updated_actor_id&.nonzero?
      user = User.find_by(id: suggested_fix_alert&.state_updated_actor_id)
      if user.nil?
        user = User.ghost
      elsif user.hide_from_user?(current_user)
        # if the actor is hidden from the current user, treat it as if we have no actor
        user = nil
      end
    else
      user = nil
    end

    user
  end

  def state_updated_at
    suggested_fix_alert&.state_updated_at
  end

  def autofix_enabled?
    CodeScanning::Autofix.enabled_for_tool?(repository, tool_name)
  end

  def show_thirdparty_beta_badge?
    CodeScanning::AutofixThirdPartyTools.is_supported_tool?(tool_name)
  end

  def show_workspace_editor?
    current_user&.workspace_editor_preview_enabled?(repository: repository)
  end

  def show_copilot_feedback_actions?
    !@skip_interactive_elements
  end

  def copilot_feedback_options
    labels = code_quality? ? FEEDBACK_LABELS_CODE_QUALITY : FEEDBACK_LABELS
    CodeScanning::Autofix::FEEDBACK_OPTIONS.map { |value| { value: value, label: labels[value] } }
  end

  def feedback_path
    if code_quality?
      pull_request_code_quality_autofix_feedback_path(repository.owner, repository, pull_request, pull_request_review_comment)
    else
      pull_request_code_scanning_autofix_feedback_path(repository.owner, repository, pull_request, alert_number)
    end
  end

  def tool_name
    return alert_details.tool_name if code_quality?

    code_scanning_alert = T.cast(annotation_result, T.nilable(Turboscan::Proto::AnnotationResult))
    return code_scanning_alert.result&.tool&.name unless code_scanning_alert.nil?

    alert_details.tool_name
  end

  def pending_suggested_fix_with_timeout_wrapper(&block)
    wait_until = pull_request_review_comment.created_at + 10.minutes
    delay = wait_until - Time.zone.now

    content_tag(
      "timeout-content",
      {
        class: "review-comment border-top",
        "data-delay-ms": delay.in_milliseconds.ceil,
      }.merge(test_selector_data_hash("ai-suggested-fix-pending")),
      &block
    ) if delay > 0
  end

  def autofix_suggestion_commit_title
    return "Potential fix for code quality finding '#{alert_details.alert_title}'" if code_quality?

    CodeScanning::AutofixCommit.message_for_alert(alert_number: turboscan_alert_number, alert_title: fallback_alert_title)
  end

  def alive_attrs
    return {} unless autofix_enabled?

    {
      class: "js-socket-channel js-updatable-content",
      data: {
        channel: live_update_view_channel(GitHub::WebSocket::Channels.pull_request(pull_request)),
        url: data_url,
        gid: pull_request.global_relay_id,
      }
    }
  end

  def data_url
    # We pass an an alert_number, but it is unused
    # This means that it is okay to pass an alert number for code quality comments
    pull_request_code_scanning_autofix_review_comment_partial_path(
      repository.owner,
      repository,
      pull_request,
      alert_number || 0,
      comment_id: pull_request_review_comment.id
    )
  end

  def suggested_fix_file_edit_path
    edit_path_params = {
      pull_request_number: pull_request.number,
    }
    if code_quality?
      edit_path_params.merge!({
        code_quality_review_comment_id: pull_request_review_comment.id,
        variant: "code_quality"
      })
    else
      edit_path_params.merge!({
        alert_number: alert_number,
        variant: "code_scanning"
      })
    end
    file_edit_path(repository.owner, repository, pull_request.head_ref_name, suggested_fix_diff_entries[0].path, **edit_path_params)
  end

  def diff_component_hydro_click_tracking_payload
    if code_quality?
      {
        repository_id: repository.id,
        pull_request_id: pull_request.id,
        pull_request_number: pull_request.number,
        review_comment_id: pull_request_review_comment.id,
        finding_stable_id: code_quality_finding&.stable_id,
        type: :code_quality,
      }
    else
      {
        repository_id: repository.id,
        alert_number: alert_number,
        pull_request_id: pull_request.id,
        pull_request_number: pull_request.number,
        type: :code_scanning,
      }
    end
  end

  # Duplicates functionality from CodeScanning::AnnotationComponent#result_resolved?
  def code_scanning_alert_resolved?
    if (finding = code_quality_finding).present? # assigned to a variable since sorbet doesn't understand memoization
      finding.resolved?
    else
      resolution = T.cast(annotation_result, T.nilable(Turboscan::Proto::AnnotationResult))&.result&.resolution
      resolution.present? && resolution != :NO_RESOLUTION
    end
  end

  def suggested_fix_not_supported
    CodeScanning::Autofix.suggested_autofix_not_supported_message(suggested_fix_rule_name)
  end

  def suggested_fix_autofix_docs_url
    DocsUrlConfig.url_for("about-autofix")
  end

  def thirdparty_autofix_docs_url
    CodeScanning::AutofixThirdPartyTools.changelog_url
  end

  def pending_dismissal_request?
    return false unless CodeScanning::AlertDismissalService.new(repository).delegated_dismissal_enabled?

    pending_dismissal_request.present?
  end

  def pending_dismissal_requester
    pending_dismissal_request&.requester
  end

  def pending_dismissal_resolution
    return if !pending_dismissal_request?
    alert_closure_reasons[Turboscan::Proto::ResultResolution.lookup(pending_dismissal_request&.metadata["resolution"].to_i)].downcase
  end

  def pending_dismissal_requested_at
    Google::Protobuf::Timestamp.new(seconds: pending_dismissal_request&.created_at.to_i)
  end

  def rejected_request?
    return false unless CodeScanning::AlertDismissalService.new(repository).delegated_dismissal_enabled?

    rejected_request.present?
  end

  def request_rejector
    rejected_request&.responses.last&.reviewer
  end

  def rejected_at
    Google::Protobuf::Timestamp.new(seconds: rejected_request&.updated_at.to_i)
  end

  private

  memoize def pending_dismissal_request
    return nil if code_quality? # Code Quality does not support dismissal requests

    CodeScanning::AlertDismissalService.find_pending_request(repository: repository, alert_number: turboscan_alert_number)
  end

  memoize def rejected_request
    return nil if code_quality? # Code Quality does not support dismissal requests

    CodeScanning::AlertDismissalService.find_rejected_request(repository: repository, alert_number: turboscan_alert_number)
  end

  def suggested_fix_rule_name
    suggested_fix_alert&.rule_sarif_identifier
  end

  def suggested_fix_rule_unsupported?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
  end
end
