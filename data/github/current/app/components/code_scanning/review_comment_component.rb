# typed: true
# frozen_string_literal: true

class CodeScanning::ReviewCommentComponent < ApplicationComponent
  extend T::Sig
  include CodeScanningHelper

  def self.preload_review_comments(pull_request:)
    pull_request.async_preload_code_scanning_alerts
    pull_request.async_preload_code_scanning_suggested_fixes
    pull_request.code_scanning_review_comments
  end

  attr_reader :pull_request_review_comment, :pull_request

  def initialize(pull_request_review_comment:, pull_request:, comment_context: nil)
    @pull_request_review_comment = pull_request_review_comment
    @pull_request = pull_request
  end

  memoize def code_scanning_review_comment
    pull_request.code_scanning_review_comment_for_comment(@pull_request_review_comment.id)
  end

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
    return false unless suggested_fix? # Don't show the suggested fix if there isn't one
    return false if invalid_suggested_fix? # Don't show the suggested fix if it is invalid

    true
  end

  memoize def show_suggested_fix_actions?
    return false if dismissed_suggested_fix?
    return false if applied_suggested_fix?
    return false if outdated_suggested_fix?
    return false if code_scanning_alert_resolved?

    pull_request.can_apply_code_scanning_suggested_fix?(current_user)
  end

  def hide_suggested_fix_summary?
    !collapse_suggested_fix? # Only show the summary if the suggested fix is collapsed
  end

  def collapse_suggested_fix?
    dismissed_suggested_fix? || applied_suggested_fix?
  end

  def collapsed_suggested_fix_message
    if dismissed_suggested_fix?
      "This autofix suggestion was marked as dismissed."
    elsif applied_suggested_fix?
      "This autofix suggestion was applied."
    end
  end

  memoize def show_suggested_fix_actioned_message?
    return true if dismissed_suggested_fix?
    return true if applied_suggested_fix?

    false
  end

  memoize def suggested_fix_actioned_message
    if dismissed_suggested_fix?
      "dismissed this autofix suggestion"
    elsif applied_suggested_fix?
      "commited this autofix suggestion"
    end
  end

  sig { returns(T.nilable(String)) }
  memoize def suggested_fix_actioned_by_unknown_user_message
    if dismissed_suggested_fix?
      "This autofix suggestion was dismissed"
    elsif applied_suggested_fix?
      "This autofix suggestion was applied"
    end
  end

  memoize def suggested_fix_description
    GitHub::Goomba::MarkdownPipeline.to_html(suggested_fix&.description)
  end

  memoize def suggested_fix_diff_entries
    suggested_fix.files.each_with_object([]) do |file, out|
      parser = GitHub::Diff::Parser.new(file.diff_content)
      parser.each { |entry| out << entry }
    end
  rescue GitHub::Diff::Parser::UnrecognizedText => err
    # report the error to Sentry
    Failbot.report!(err)
    []
  end

  memoize def suggested_fix_file_highlighting
    suggested_fix_diff_entries.each_with_object({}) do |diff_entry, out|
      out[diff_entry.path] = DiffEntryHighlighting.new(diff_entry).highlight_lines
    end
  end

  def suggested_fix_dependency_metadata?
    suggested_fix_dependency_metadata.any?
  end

  def suggested_fix_dependency_metadata
    suggested_fix&.dependency_metadata
  end

  def annotation_wrapper(&block)
    yield
    nil # Returning `yield` causes a double render
  end

  def suggested_fix?
    suggested_fix.present? && suggested_fix_diff_entries.any?
  end

  memoize def dismissed_suggested_fix?
    return false unless suggested_fix?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_DISMISSED
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

  def can_have_suggested_fix?
    return false unless CodeScanning::Autofix.enabled_for_repo?(repository)

    tool_name = if code_scanning_alert.present?
      code_scanning_alert.result&.tool&.name
    else
      code_scanning_review_comment.tool_name
    end

    return false unless CodeScanning::Autofix.generate_for_tool?(repository, tool_name)

    true
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
    "Apply code scanning fix for #{code_scanning_review_comment.alert_title.downcase}" if code_scanning_review_comment.alert_title.present?
  end

  def autofix_edit_cli_title
    "Edit with GitHub CLI"
  end

  def alive_attrs
    return {} unless CodeScanning::Autofix.enabled_for_repo?(repository)

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
    pull_request_code_scanning_auto_fix_review_comment_partial_path(
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

  def suggested_fix_show_not_supported?
    suggested_fix_language_unsupported? || suggested_fix_rule_unsupported?
  end

  def suggested_fix_not_supported
    if suggested_fix_language_unsupported?
      prefix = suggested_fix_rule_name.split("/").first.to_sym
      CodeScanningHelper::AUTOFIX_RULES_LANGUAGE_MAP.fetch(prefix, "Language")
    else
      "Rule #{suggested_fix_rule_name}"
    end
  end

  def suggested_fix_autofix_docs_url
    DocsUrlConfig.url_for("about-autofix")
  end

  private

  def suggested_fix_rule_name
    suggested_fix_alert.rule_sarif_identifier
  end

  def suggested_fix_language_unsupported?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_LANGUAGE_NOT_SUPPORTED
  end

  def suggested_fix_rule_unsupported?
    suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
  end
end
