# typed: true
# frozen_string_literal: true

class Dependabot::ReviewCommentComponent < ApplicationComponent
  FEEDBACK_LABELS = {
    DEPENDABOT_AUTOFIX_FEEDBACK_FIX_HAS_ERRORS: "The fix is partially correct, but has errors",
    DEPENDABOT_AUTOFIX_FEEDBACK_FIX_IS_UNHELPFUL: "The fix is not helpful at all",
    DEPENDABOT_AUTOFIX_FEEDBACK_FIX_WONT_ADDRESS_PROBLEM: "Unsure if this fix will address the security vulnerability",
    DEPENDABOT_AUTOFIX_FEEDBACK_FIX_WILL_BREAK_FUNCTIONALITY: "Unsure if this fix will break code functionality",
    DEPENDABOT_AUTOFIX_FEEDBACK_OTHER: "Other reason"
  }

  attr_reader :pull_request_review_comment, :pull_request

  def initialize(pull_request_review_comment:, pull_request:, comment_context: nil)
    @pull_request_review_comment = pull_request_review_comment
    @pull_request = pull_request
  end

  memoize def dependabot_review_comment
    pull_request.dependabot_review_comment_for_comment(@pull_request_review_comment, @pull_request.number)
  end

  memoize def dependabot_annotation
    pull_request.dependabot_annotation_for_review_comment(@pull_request_review_comment)
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

  memoize def suggested_fix_for_autofix_job
    pull_request.dependabot_suggested_fix_autofix_job(dependabot_review_comment)
  end

  def suggested_fix_for_autofix_job?
    suggested_fix_for_autofix_job.present?
  end

  # TODO: Currently, if the suggested fix is nil, we won’t display the suggested fix
  # and will instead show an error message. In the future, this should be updated to
  # validate the suggested fix before deciding
  def suggested_fix_error?
    false unless suggested_fix?
  end

  memoize def suggested_fix
    suggested_fix_for_autofix_job
  end

  memoize def show_suggested_fix?
    return false unless suggested_fix? # Don't show the suggested fix if there isn't one
    # TODO: Implement invalid_suggested_fix? to use correct state in the future
    # return false if invalid_suggested_fix? # Don't show the suggested fix if it is invalid

    true
  end

  memoize def show_suggested_fix_actions?
    return false if applied_suggested_fix?
    return false if outdated_suggested_fix?

    pull_request.can_apply_code_scanning_suggested_fix?(current_user)
  end

  def hide_suggested_fix_summary?
    !collapse_suggested_fix? # Only show the summary if the suggested fix is collapsed
  end

  def collapse_suggested_fix?
    applied_suggested_fix?
  end

  def collapsed_suggested_fix_message
    "This autofix suggestion was applied." if applied_suggested_fix?
  end

  memoize def show_suggested_fix_actioned_message?
    applied_suggested_fix?
  end

  memoize def suggested_fix_actioned_message
    "committed this autofix suggestion" if applied_suggested_fix?
  end

  sig { returns(T.nilable(String)) }
  memoize def suggested_fix_actioned_by_unknown_user_message
    "This autofix suggestion was applied" if applied_suggested_fix?
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

  memoize def applied_suggested_fix?
    return false unless suggested_fix?
    [
      DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus::STATUS_APPROVED,
      DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus.lookup(
        DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus::STATUS_APPROVED
      )
    ].include?(suggested_fix&.review_status)
  end

  memoize def unreviewed_suggested_fix?
    return false unless suggested_fix_for_autofix_job?
    [
      DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus::STATUS_UNREVIEWED,
      DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus.lookup(
        DependabotApi::V1::SuggestedFix::SuggestedFixReviewStatus::STATUS_UNREVIEWED
      )
    ].include?(suggested_fix&.review_status)
  end

  # TODO: Implement outdated_suggested_fix? in the future
  def outdated_suggested_fix?
    return false unless suggested_fix?

    # If suggested fix unreviewed, it shouldn't be considered outdated
    return false if unreviewed_suggested_fix?

    # If suggested fix is applied, check if it should be considered outdated
    applied_suggested_fix? ? false : true
  end

  sig { returns(T.nilable(User)) }
  memoize def state_updated_by
    # We don't track this in dependabot autofixes yet
    nil
    # if suggested_fix_for_autofix_job&.state_updated_actor_id&.nonzero?
    #   user = User.find_by(id: suggested_fix_for_autofix_job&.state_updated_actor_id)
    #   if user.nil?
    #     user = User.ghost
    #   elsif user.hide_from_user?(current_user)
    #     # if the actor is hidden from the current user, treat it as if we have no actor
    #     user = nil
    #   end
    # else
    #   user = nil
    # end

    # user
  end

  def state_updated_at
    suggested_fix_for_autofix_job&.updated_at
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
    "#{dependabot_review_comment.fallback_annotation_title.downcase}" if dependabot_review_comment.fallback_annotation_title.present?
  end

  def autofix_edit_cli_title
    "Edit with GitHub CLI"
  end

  def alive_attrs
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
    pull_request_dependabot_autofix_review_comment_partial_path(
      repository.owner,
      repository,
      pull_request,
      dependabot_review_comment.autofix_job_id,
      comment_id: pull_request_review_comment.id
    )
  end

  def copilot_feedback_options
    Dependabot::Autofix::FEEDBACK_OPTIONS.map { |value| { value: value, label: FEEDBACK_LABELS[value] } }
  end
end
