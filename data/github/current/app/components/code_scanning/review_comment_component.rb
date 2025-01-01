# typed: true
# frozen_string_literal: true

class CodeScanning::ReviewCommentComponent < ApplicationComponent
  include CodeScanningHelper

  FEEDBACK_LABELS = {
    CODE_SCANNING_AUTOFIX_FEEDBACK_ALERT_NOT_RELEVANT: "The alert is not relevant, and no fix is needed",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_HAS_ERRORS: "The fix is partially correct, but has errors",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_IS_UNHELPFUL: "The fix is not helpful at all",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WONT_ADDRESS_PROBLEM: "Unsure if this fix will address the security vulnerability",
    CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WILL_BREAK_FUNCTIONALITY: "Unsure if this fix will break code functionality",
    CODE_SCANNING_AUTOFIX_FEEDBACK_OTHER: "Other reason"
  }

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
    skip_view_patch_menu_item: false
  )
    @autofix_header_type = autofix_header_type
    @pull_request_review_comment = pull_request_review_comment
    @pull_request = pull_request
    @skip_interactive_elements = skip_interactive_elements
    @skip_view_patch_menu_item = skip_view_patch_menu_item
  end

  memoize def code_scanning_review_comment
    pull_request.code_scanning_review_comment_for_comment(@pull_request_review_comment.id)
  end

  def fallback_alert_title
    code_scanning_review_comment.alert_title
  end

  def fallback_alert_message
    code_scanning_review_comment.alert_message
  end

  sig { returns(T.nilable(Turboscan::Proto::AnnotationResult)) }
  memoize def code_scanning_alert
    pull_request.code_scanning_alert_for_review_comment(@pull_request_review_comment)
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

  memoize def suggested_fix_alert
    pull_request.code_scanning_suggested_fix_alert(code_scanning_review_comment.alert_number)
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
    suggested_fix_alert.state == :SUGGESTED_FIX_ALERT_STATE_INVALID
  end

  def outdated_suggested_fix?
    return false unless suggested_fix?
    suggested_fix.outdated
  end

  sig { returns(T.nilable(User)) }
  memoize def state_updated_by
    if suggested_fix_alert&.state_updated_actor_id&.nonzero?
      user = User.find_by(id: suggested_fix_alert.state_updated_actor_id)
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
    CodeScanning::Autofix::FEEDBACK_OPTIONS.map { |value| { value: value, label: FEEDBACK_LABELS[value] } }
  end

  def tool_name
    return code_scanning_alert&.result&.tool&.name unless code_scanning_alert.nil?

    code_scanning_review_comment.tool_name
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
    CodeScanning::AutofixCommit.message_for_alert(alert_number: code_scanning_review_comment.alert_number, alert_title: fallback_alert_title)
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
    pull_request_code_scanning_autofix_review_comment_partial_path(
      repository.owner,
      repository,
      pull_request,
      code_scanning_review_comment.alert_number,
      comment_id: pull_request_review_comment.id
    )
  end

  # Duplicates functionality from CodeScanning::AnnotationComponent#result_resolved?
  def code_scanning_alert_resolved?
    resolution = code_scanning_alert&.result&.resolution
    resolution.present? && resolution != :NO_RESOLUTION
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
    return false unless CodeScanning::AlertDismissalService.new(repository).enabled?

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
    return false unless CodeScanning::AlertDismissalService.new(repository).enabled?

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
    CodeScanning::AlertDismissalService.find_pending_request(repository: repository, alert_number: code_scanning_review_comment.alert_number)
  end

  memoize def rejected_request
    CodeScanning::AlertDismissalService.find_rejected_request(repository: repository, alert_number: code_scanning_review_comment.alert_number)
  end

  def suggested_fix_rule_name
    suggested_fix_alert.rule_sarif_identifier
  end

  def suggested_fix_rule_unsupported?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
  end
end
