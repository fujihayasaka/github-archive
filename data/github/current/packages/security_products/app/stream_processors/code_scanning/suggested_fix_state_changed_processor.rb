# typed: strict
# frozen_string_literal: true

module CodeScanning
  # Turboscan sends a message to hydro every time a suggested fix's state changes.
  # This processor updates the state of the automated review comment suggested fixes.
  # It also notifies the websocket PR and repository channels for UI reloads.
  class SuggestedFixStateChangedProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    include GitHub::StreamProcessors::TransientErrorResiliency
    include GitHub::Memoizer

    class Error < StandardError; end

    DEFAULT_GROUP_ID = "code_scanning_suggested_fix_state_changed"
    DEFAULT_SUBSCRIBE_TO = T.let([
      /code_scanning\.v0\.SuggestedFixStateChanged\Z/,
    ].freeze, T::Array[Regexp])
    DEFAULT_FUNCTION_LABEL = "CodeScanning::SuggestedFixStateChangedProcessor"

    options[:min_bytes] = 5.kilobytes
    options[:max_wait_time] = 0.2.seconds
    options[:max_bytes_per_partition] = 100.kilobytes
    options[:session_timeout] = 60.seconds
    options[:start_from_beginning] = false

    # Stream processor scoping all queries to the tenant associated with the message's repository
    resolve_tenant_context do |message|
      Repositories::Public.get_active_or_deleted(message.value[:repository_id])&.owner&.business
    end

    sig { params(group_id: T.nilable(String), subscribe_to: T.nilable(T::Array[Regexp])).void }
    def setup(group_id: nil, subscribe_to: nil)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      self.transient_error_max_retries = 20
    end

    sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
    def process_message(message)
      values = message.value
      repository_id = values[:repository_id]
      pull_request_id = values[:pull_request_id]
      alert_number = values[:alert_number]
      commit_oid = values[:commit_oid]
      state = values[:state]
      suggested_fix = values[:suggested_fix] ? Hydro::Schemas::CodeScanning::V0::Entities::SuggestedFix.new(values[:suggested_fix]) : nil

      logging_context.merge!(
        "gh.repo.id" => repository_id,
        "gh.pull_request.id" => pull_request_id,
        "gh.alert.number" => alert_number,
        "gh.commit.oid" => commit_oid,
        "gh.suggested_fix.state" => state,
        "gh.suggested_fix.present" => suggested_fix.present?
      )

      log_info("Received new suggested fix state changed message")

      # Return if we don't have a repository
      repository = T.cast(::Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      if repository.nil?
        log_error("Repository not found, skipping processing")
        return
      end

      # Return if we don't have a commit OID; downstream logic assumes it is present
      if commit_oid.nil?
        log_error("Commit OID missing from suggested fix state changed message, skipping processing")
        return
      end

      # Return if we don't have an alert number
      if alert_number.blank?
        log_error("Missing alert number in message, skipping processing")
        return
      end

      # Return unless code scanning feature flags are enabled
      unless feature_flags_enabled?(repository)
        log_error("Code scanning features not enabled for repository or org, skipping processing")
        return
      end

      pull_request = pull_request_id && PullRequest.find_by(repository:, id: pull_request_id)
      # If we have a pull request, we need to update the corresponding automated review comments and notify the PR channel for a live reload.
      if pull_request
        automated_review_comments = AutomatedReviewComment.where(
          repository: repository,
          pull_request_id: pull_request_id,
          source: :source_code_scanning,
          fixed_at: nil,
          resource_id: alert_number.to_s
        ).to_a

        if automated_review_comments.size > 1
          log_info(
            "Unexpected automated review comments count: multiple matching comments found for alert on pull request",
            "gh.comments.count" => automated_review_comments.size,
          )
        end

        if automated_review_comments.empty?
          log_info("No matching automated review comments found for alert on pull request")
        else
          # Update ARC suggestion_state and suggestion data using the existing ReviewComments::Suggestion model
          with_primaries ApplicationRecord::IssuesPullRequests do
            updated_review_comment_ids = []
            automated_review_comments.each do |comment|
              updated = handle_suggestion_state(comment, pull_request, state, suggested_fix, commit_oid)

              next unless updated
              updated_review_comment_ids << comment.pull_request_review_comment_id
            end

            # Trigger WebSocket PR reviews live reloads
            review_ids = PullRequestReviewComment.where(id: updated_review_comment_ids.to_a).distinct.pluck(:pull_request_review_id)
            reviews_to_notify = PullRequestReview.where(id: review_ids).to_a
            log_info(
              "Notifying pull request review socket subscribers",
              "gh.code_scanning.updated_comments_count" => updated_review_comment_ids.size,
              "gh.code_scanning.notify_reviews_count" => reviews_to_notify.size,
            )
            notify_reviews(reviews_to_notify)
          end
        end
      end

      # We notify the alert channel (which will trigger a reload on the alert details page if it's open).
      log_info("Notify alert websocket channel as suggested fix state changed")

      channel = GitHub::WebSocket::Channels.code_scanning_alert(repository, alert_number:)
      GitHub::WebSocket.notify_repository_channel(repository, channel, { has_valid_suggested_fix: state == :VALID })
    end

    private

    sig { params(repository: Repository).returns(T::Boolean) }
    def feature_flags_enabled?(repository)
      arc_enabled = repository.feature_flag_enabled?(:code_scanning_automated_review_comment, default: false) || !!repository.owner&.feature_flag_enabled?(:code_scanning_automated_review_comment, default: false)
      hydro_autofix_enabled = repository.feature_flag_enabled?(:code_scanning_hydro_autofix, default: false) || !!repository.owner&.feature_flag_enabled?(:code_scanning_hydro_autofix, default: false)
      arc_enabled && hydro_autofix_enabled
    end

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_info(message, context = {})
      GitHub.logger.info(message, logging_context.merge(context))
    end

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_error(message, context = {})
      GitHub.logger.error(message, logging_context.merge(context))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    memoize def logging_context
      {
        "code.namespace" => DEFAULT_FUNCTION_LABEL,
        "code.function" => DEFAULT_FUNCTION_LABEL
      }
    end

    sig { params(message: GitHub::StreamProcessors::Message).returns(T::Hash[Symbol, T.untyped]) }
    def error_context_for_message(message)
      super(message).merge(
        repo_id: message.value[:repository_id],
        analyzed_commit_oid: message.value[:commit_oid]
      )
    end

    sig do
      params(reviews: T::Array[PullRequestReview]).void
    end
    def notify_reviews(reviews)
      reviews.each(&:notify_socket_subscribers)
    end

    sig { params(comment: AutomatedReviewComment, pull_request: PullRequest, state: Symbol, suggested_fix: T.nilable(Hydro::Schemas::CodeScanning::V0::Entities::SuggestedFix), commit_oid: String).returns(T::Boolean) }
    def handle_suggestion_state(comment, pull_request, state, suggested_fix, commit_oid)
      # Handle pending state
      if state == :PENDING
        comment.update!(suggestion_state: :suggestion_state_pending)

        log_info("Synced automated review comment suggestion")
        return true
      end

      # Handle error/invalid states
      if state.in?([:ERROR, :INVALID, :RULE_NOT_SUPPORTED])
        error_message = error_message_for_state(state)
        comment.update!(
          suggestion_state: :suggestion_state_error,
          suggestion_error_message: error_message
        )
        log_info("Synced automated review comment suggestion", "gh.code_scanning.suggestion_error" => error_message)
        return true
      end

      # Ignore applied state
      # The state transition to `applied` is handled beforehand in `AutomatedReviewComment#apply_suggestion!`
      if state == :APPLIED
        log_info("Skipped automated review comment suggestion sync")
        return false
      end

      if state == :VALID
        # Valid state with no suggestion data is treated as no suggestion
        if suggested_fix.nil?
          comment.update!(suggestion_state: :suggestion_state_no_suggestion)
          log_info("Missing suggestion data for valid state")
          return true
        end

        # Note(@aliceclv): In the context of pull request and automated review comment, we consider the fix outdated if the commit OID doesn't match the pull request's head SHA.
        # This is aligned with the current handling of outdated suggestions for automated review comment
        # Once CCR has implemented the outdated suggestion state handling, we should update this logic
        # See https://github.com/github/copilot-code-review/issues/1030
        if commit_oid != pull_request.head_sha
          log_info("Skipped automated review comment suggestion sync due to outdated suggestion", "gh.code_scanning.suggestion_outdated" => true)
          return false
        end

        # Build and store the suggestion
        comment.suggestion = build_suggestion(suggested_fix, commit_oid)
        comment.suggestion_state = :suggestion_state_present
        comment.save!

        log_info("Synced automated review comment suggestion")
        return true
      end

      log_info("Unhandled suggested fix state")
      false
    end

    sig { params(state: Symbol).returns(String) }
    def error_message_for_state(state)
      case state
      when :ERROR
        "Failed to generate autofix suggestion"
      when :INVALID
        "Autofix suggestion is invalid"
      when :RULE_NOT_SUPPORTED
        "Autofix is not supported for this rule"
      else
        "Unknown error"
      end
    end

    sig { params(suggested_fix: Hydro::Schemas::CodeScanning::V0::Entities::SuggestedFix, commit_oid: String).returns(ReviewComments::Suggestion) }
    def build_suggestion(suggested_fix, commit_oid)
      files = suggested_fix.files.map do |file|
        ReviewComments::Suggestion::File.new(
          path: file.file_path,
          diff_content: file.diff_content
        )
      end

      ReviewComments::Suggestion.new(
        commit_sha: commit_oid,
        files: files
      )
    end
  end
end
