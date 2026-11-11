# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AutomatedReviewCommentSuggestionFromTurboscan
    include GitHub::Memoizer

    sig do
      params(
        pull_request: PullRequest,
        alert_numbers: T::Array[Integer]
      ).void
    end
    def self.sync(pull_request:, alert_numbers:)
      instance = new(pull_request: pull_request, alert_numbers: alert_numbers)
      instance.sync
      instance.notify_reviews
    end

    sig { params(comment: AutomatedReviewComment).void }
    def self.sync_or_timeout_pending(comment)
      pull_request = comment.pull_request
      return if pull_request.nil?

      alert_number = comment.resource_id.to_i
      instance = new(pull_request:, alert_numbers: [alert_number])
      if instance.pending_suggested_fix_alert?(alert_number)
        CodeScanning::AutomatedReviewCommentSuggestionState.timeout_pending!(comment)
      else
        instance.sync_comment(comment)
        instance.notify_reviews
      end
    rescue CodeScanning::AutofixError => error
      GitHub.logger.info(
        "Timing out pending suggestion after Turboscan fetch failure",
        "gh.automated_review_comment.id" => comment.id,
        "gh.automated_review_comment.resource_id" => comment.resource_id,
        "gh.pull_request.id" => comment.pull_request_id,
        "gh.repo.id" => comment.repository_id,
        "gh.error.message" => error.message,
      )
      CodeScanning::AutomatedReviewCommentSuggestionState.timeout_pending!(comment)
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

      @changed_review_comment_ids = T.let(Set.new, T::Set[Integer])
      @processed_comments_count = T.let(0, Integer)
      @changed_comments_count = T.let(0, Integer)
    end

    sig { void }
    def sync
      return if @alert_numbers.empty?

      GitHub.logger.with_named_tags(
        "code.namespace" => "CodeScanning::AutomatedReviewCommentSuggestionTurboscanSync",
        "code.function" => "sync",
        **logging_context
      ) do
        comments = AutomatedReviewComment.where(
          repository: repository,
          pull_request: @pull_request,
          source: :source_code_scanning,
          fixed_at: nil,
          resource_id: @alert_numbers.map(&:to_s)
        )

        comments_count = comments.count
        if comments_count != @alert_numbers.size
          GitHub.logger.warn(
            "Count mismatch when syncing suggestions",
            "gh.code_scanning.mismatch_resource" => "comments",
            "gh.code_scanning.expected_count" => @alert_numbers.size,
            "gh.code_scanning.actual_count" => comments_count,
          )
        end
        return if comments_count.zero?

        if suggested_fix_alerts.size != @alert_numbers.size
          GitHub.logger.warn(
            "Count mismatch when syncing suggestions",
            "gh.code_scanning.mismatch_resource" => "suggested_fix_alerts",
            "gh.code_scanning.expected_count" => @alert_numbers.size,
            "gh.code_scanning.actual_count" => suggested_fix_alerts.size,
          )
        end

        comments.find_each do |comment|
          sync_comment(comment)
        end
      end
    end

    sig { params(comment: AutomatedReviewComment).void }
    def sync_comment(comment)
      GitHub.logger.with_named_tags(
        "code.namespace" => "CodeScanning::AutomatedReviewCommentSuggestionTurboscanSync",
        "code.function" => "sync_comment",
        **logging_context
      ) do
        @processed_comments_count += 1
        alert_number = comment.resource_id.to_i

        comment.assign_attributes(build_comment_attributes(alert_number))
        if comment.changed?
          attributes = {
            "gh.automated_review_comment.id" => comment.id,
            "gh.automated_review_comment.resource_id" => comment.resource_id,
            "gh.automated_review_comment.suggestion_state" => comment.read_attribute(:suggestion_state),
            "gh.automated_review_comment.suggestion_error_message" => comment.read_attribute(:suggestion_error_message),
          }

          begin
            comment.save!
          rescue JSON::GeneratorError => error
            repository = T.must(comment.repository)
            if FeatureFlag.vexi.enabled?(:code_scanning_arc_suggestion_json_generator_error_handling, repository, repository.owner, default: false)
              GitHub.dogstats.increment("code_scanning.automated_review_comment.suggestion.serialization_failed")

              GitHub.logger.warn("Failed to serialize JSON", attributes.merge(
                "gh.error.class" => error.class.name,
                "gh.automated_review_comment.id" => comment.id,
                "gh.automated_review_comment.resource_id" => comment.resource_id,
              ))

              comment.update!(
                suggestion: nil,
                suggestion_state: :suggestion_state_error,
                suggestion_error_message: "Failed to generate autofix suggestion",
              )
            else
              raise
            end
          end

          GitHub.logger.info("Synced suggestion to AutomatedReviewComment", attributes)

          @changed_comments_count += 1

          review_comment_id = comment.pull_request_review_comment_id
          @changed_review_comment_ids.add(review_comment_id)
        end
      end
    end

    sig { void }
    def notify_reviews
      review_ids = PullRequestReviewComment.where(id: @changed_review_comment_ids.to_a).distinct.pluck(:pull_request_review_id)
      reviews_to_notify = PullRequestReview.where(id: review_ids).to_a

      GitHub.logger.info(
        "Notifying pull request review socket subscribers",
        "gh.code_scanning.comments_processed_count" => @processed_comments_count,
        "gh.code_scanning.comments_changed_count" => @changed_comments_count,
        "gh.code_scanning.notify_reviews_count" => reviews_to_notify.size,
      )

      reviews_to_notify.each(&:notify_socket_subscribers)
    end

    sig { params(alert_number: Integer).returns(T::Boolean) }
    def pending_suggested_fix_alert?(alert_number)
      suggested_fix_alert = suggested_fix_alert_for(alert_number)
      suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_PENDING
    end

    private

    sig { returns(T.nilable(Repository)) }
    def repository
      @pull_request.repository
    end

    sig { returns(T::Hash[Integer, T.untyped]) }
    memoize def suggested_fix_alerts
      CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
        repository: repository,
        alert_numbers: @alert_numbers,
        head_commit_oid: head_commit_oid,
        ref_names_bytes: ref_names_bytes,
        merge_commit_oid: merge_commit_oid
      )
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

    sig { returns(T::Hash[String, T.untyped]) }
    def logging_context
      {
        "gh.repo.id" => @pull_request.repository_id,
        "gh.pull_request.id" => @pull_request.id,
        "gh.code_scanning.alert_numbers" => @alert_numbers.join(","),
        "gh.code_scanning.head_commit_oid" => head_commit_oid,
        "gh.code_scanning.ref_names_bytes" => ref_names_bytes.join(","),
        "gh.code_scanning.merge_commit_oid" => merge_commit_oid,
      }
    end

    sig { params(alert_number: Integer).returns(T.untyped) }
    def suggested_fix_alert_for(alert_number)
      if @alert_numbers.exclude?(alert_number)
        raise ArgumentError, "Cannot retrieve suggested fix alert for alert number not specified in alert_numbers"
      end

      suggested_fix_alerts[alert_number]
    end

    sig { params(alert_number: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def build_comment_attributes(alert_number)
      suggested_fix_alert = suggested_fix_alert_for(alert_number)

      if suggested_fix_alert
        {
          suggestion_state: to_suggestion_state(suggested_fix_alert.state),
          suggestion_error_message: to_suggestion_error_message(suggested_fix_alert.state),
          suggestion: build_suggestion(suggested_fix_alert.suggested_fix),
        }
      else
        {
          suggestion_state: :suggestion_state_no_suggestion,
          suggestion_error_message: nil,
          suggestion: nil,
        }
      end
    end

    sig { params(state: Symbol).returns(T.nilable(Symbol)) }
    def to_suggestion_state(state)
      case state
      when :SUGGESTED_FIX_ALERT_STATE_PENDING
        :suggestion_state_pending
      when :SUGGESTED_FIX_ALERT_STATE_ERROR, :SUGGESTED_FIX_ALERT_STATE_INVALID, :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
        :suggestion_state_error
      when :SUGGESTED_FIX_ALERT_STATE_APPLIED
        :suggestion_state_applied
      when :SUGGESTED_FIX_ALERT_STATE_VALID, :SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP
        :suggestion_state_present
      end
    end

    sig { params(state: Symbol).returns(T.nilable(String)) }
    def to_suggestion_error_message(state)
      case state
      when :SUGGESTED_FIX_ALERT_STATE_ERROR
        "Failed to generate autofix suggestion"
      when :SUGGESTED_FIX_ALERT_STATE_INVALID
        "Autofix suggestion is invalid"
      when :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED
        "Autofix is not supported for this rule"
      end
    end

    sig { params(suggested_fix: T.untyped).returns(T.nilable(ReviewComments::Suggestion)) }
    def build_suggestion(suggested_fix)
      return nil if suggested_fix.nil?

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
  end
end
