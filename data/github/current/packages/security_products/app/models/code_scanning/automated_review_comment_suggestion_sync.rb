# typed: strict
# frozen_string_literal: true

module CodeScanning
  # Syncs autofix suggestions from Turboscan to AutomatedReviewComment records.
  # This is used when Turboscan notifies us that suggested fix state has changed.
  class AutomatedReviewCommentSuggestionSync
    sig do
      params(
        pull_request: PullRequest,
        alert_numbers: T::Array[Integer]
      ).void
    end
    def self.sync(pull_request:, alert_numbers:)
      new(pull_request: pull_request, alert_numbers: alert_numbers).sync
    end

    sig do
      params(
        pull_request: PullRequest,
        alert_numbers: T::Array[Integer]
      ).void
    end
    def initialize(pull_request:, alert_numbers:)
      @pull_request = pull_request
      @alert_numbers = alert_numbers
    end

    sig { void }
    def sync
      return if @alert_numbers.empty?

      GitHub.logger.with_named_tags(
        "code.namespace" => "CodeScanning::AutomatedReviewCommentSuggestionSync",
        "gh.repo.id" => @pull_request.repository_id,
        "gh.pull_request.id" => @pull_request.id,
        "gh.code_scanning.alert_numbers" => @alert_numbers.join(","),
        "gh.code_scanning.head_commit_oid" => head_commit_oid,
        "gh.code_scanning.ref_names_bytes" => ref_names_bytes.join(","),
        "gh.code_scanning.merge_commit_oid" => merge_commit_oid
      ) do
        perform_sync
      end
    end

    private

    sig { void }
    def perform_sync
      comments = find_comments
      comments_count = comments.count
      if comments_count != @alert_numbers.size
        log_count_mismatch("comments", expected: @alert_numbers.size, actual: comments_count)
      end
      return if comments_count.zero?

      suggested_fix_alerts = fetch_suggested_fix_alerts
      return if suggested_fix_alerts.nil?

      if suggested_fix_alerts.size != @alert_numbers.size
        log_count_mismatch("suggested_fix_alerts", expected: @alert_numbers.size, actual: suggested_fix_alerts.size)
      end

      changed_review_comment_ids = T.let(Set.new, T::Set[Integer])
      processed_comments_count = T.let(0, Integer)
      changed_comments_count = T.let(0, Integer)

      comments.find_each do |comment|
        processed_comments_count += 1
        alert_number = comment.resource_id.to_i
        suggested_fix_alert = suggested_fix_alerts[alert_number]

        changed = sync_suggestion_to_comment(comment, suggested_fix_alert)
        next unless changed
        changed_comments_count += 1

        review_comment_id = comment.pull_request_review_comment_id
        changed_review_comment_ids.add(review_comment_id)
      end

      review_ids = PullRequestReviewComment.where(id: changed_review_comment_ids.to_a).distinct.pluck(:pull_request_review_id)
      reviews_to_notify = PullRequestReview.where(id: review_ids).to_a

      GitHub.logger.info(
        "Notifying pull request review socket subscribers",
        "gh.code_scanning.comments_count" => comments_count,
        "gh.code_scanning.comments_processed_count" => processed_comments_count,
        "gh.code_scanning.comments_changed_count" => changed_comments_count,
        "gh.code_scanning.notify_reviews_count" => reviews_to_notify.size,
      )
      notify_reviews(reviews_to_notify)
    end

    sig { returns(T.nilable(Repository)) }
    def repository
      @pull_request.repository
    end

    sig { returns(ActiveRecord::Relation) }
    def find_comments
      AutomatedReviewComment.where(
        repository: repository,
        pull_request: @pull_request,
        source: :source_code_scanning,
        fixed_at: nil,
        resource_id: @alert_numbers.map(&:to_s)
      )
    end

    sig { returns(T.nilable(T::Hash[Integer, T.untyped])) }
    def fetch_suggested_fix_alerts
      CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
        repository: repository,
        alert_numbers: @alert_numbers,
        head_commit_oid: head_commit_oid,
        ref_names_bytes: ref_names_bytes,
        merge_commit_oid: merge_commit_oid
      )
    rescue CodeScanning::AutofixError => e
      log_error("Failed to fetch suggested fixes from Turboscan", error: e.message)
      nil
    end

    sig { returns(String) }
    def head_commit_oid
      @pull_request.head_sha
    end

    sig { returns(T::Array[String]) }
    def ref_names_bytes
      @pull_request.build_ref_names_bytes_for_code_scanning_suggested_fix
    end

    sig { returns(T.nilable(String)) }
    def merge_commit_oid
      @pull_request.code_scanning_latest_check_suite&.pull_request_sha.presence
    end

    sig { params(comment: AutomatedReviewComment, suggested_fix_alert: T.untyped).returns(T::Boolean) }
    def sync_suggestion_to_comment(comment, suggested_fix_alert)
      if suggested_fix_alert.nil?
        # No suggestion data from Turboscan - leave comment unchanged
        return false
      end

      suggested_fix = suggested_fix_alert.suggested_fix
      state = suggested_fix_alert.state

      # Handle pending state
      if state == :SUGGESTED_FIX_ALERT_STATE_PENDING
        comment.update!(suggestion_state: :suggestion_state_pending)
        log_sync(comment, "pending")
        return true
      end

      # Handle error/invalid states
      if state.in?([:SUGGESTED_FIX_ALERT_STATE_ERROR, :SUGGESTED_FIX_ALERT_STATE_INVALID, :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED])
        error_message = error_message_for_state(state)
        comment.update!(
          suggestion_state: :suggestion_state_error,
          suggestion_error_message: error_message
        )
        log_sync(comment, "error", error_message: error_message)
        return true
      end

      # Ignore applied state
      # The state transition to `applied` is handled beforehand in `AutomatedReviewComment#apply_suggestion!`
      if state == :SUGGESTED_FIX_ALERT_STATE_APPLIED
        log_sync(comment, "skipped_applied")
        return false
      end

      # Handle valid states with suggestion data
      if suggested_fix.nil?
        # State indicates valid but no suggestion data - treat as no suggestion
        return false
      end

      # Skip if suggestion is outdated
      if suggested_fix.outdated
        log_sync(comment, "skipped_outdated")
        return false
      end

      # Build and store the suggestion
      comment.suggestion = build_suggestion(suggested_fix)
      comment.suggestion_state = :suggestion_state_present
      comment.save!

      log_sync(comment, "present")
      true
    end

    sig do
      params(reviews: T::Array[PullRequestReview]).void
    end
    def notify_reviews(reviews)
      reviews.each(&:notify_socket_subscribers)
    end

    sig { params(state: Symbol).returns(String) }
    def error_message_for_state(state)
      case state
      when :SUGGESTED_FIX_ALERT_STATE_ERROR
        "Failed to generate autofix suggestion"
      when :SUGGESTED_FIX_ALERT_STATE_INVALID
        "Autofix suggestion is invalid"
      when :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
        "Autofix is not supported for this rule"
      else
        "Unknown error"
      end
    end

    sig { params(suggested_fix: T.untyped).returns(ReviewComments::Suggestion) }
    def build_suggestion(suggested_fix)
      files = suggested_fix.files.map do |file|
        ReviewComments::Suggestion::File.new(
          path: file.file_path,
          diff_content: file.diff_content
        )
      end

      ReviewComments::Suggestion.new(
        commit_sha: head_commit_oid,
        files: files
      )
    end

    sig { params(comment: AutomatedReviewComment, state: String, error_message: T.nilable(String)).void }
    def log_sync(comment, state, error_message: nil)
      attributes = {
        "code.function" => "sync_suggestion_to_comment",
        "gh.automated_review_comment.id" => comment.id,
        "gh.code_scanning.alert_number" => comment.resource_id,
        "gh.code_scanning.suggestion_state" => state
      }
      attributes["gh.code_scanning.suggestion_error"] = error_message if error_message

      GitHub.logger.info("Synced suggestion to AutomatedReviewComment", attributes)
    end

    sig { params(resource: String, expected: Integer, actual: Integer).void }
    def log_count_mismatch(resource, expected:, actual:)
      GitHub.logger.warn(
        "Count mismatch when syncing suggestions",
        "code.function" => "sync",
        "gh.code_scanning.mismatch_resource" => resource,
        "gh.code_scanning.expected_count" => expected,
        "gh.code_scanning.actual_count" => actual
      )
    end

    sig { params(message: String, error: String).void }
    def log_error(message, error:)
      GitHub.logger.error(
        message,
        "code.function" => "fetch_suggested_fix_alerts",
        "error" => error
      )
    end
  end
end
