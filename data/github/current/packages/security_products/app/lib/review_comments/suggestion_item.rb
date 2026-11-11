# typed: strict
# frozen_string_literal: true

module ReviewComments
  # Common interface for suggestion items used in batch apply.
  # Both automated and user comment suggestions implement this interface.
  module SuggestionItem
    extend T::Helpers
    include Kernel
    interface!

    sig { abstract.params(pull_request: PullRequest).void }
    def validate!(pull_request); end

    sig { abstract.returns(T::Array[GitHub::Diff::Entry]) }
    def diff_entries; end

    sig { abstract.returns(T.nilable(String)) }
    def co_author_trailer; end

    sig { abstract.returns(T.nilable(Repository)) }
    def repository; end

    sig { abstract.params(user: User, pull_request: PullRequest, commit_sha: T.nilable(String)).void }
    def on_applied(user:, pull_request:, commit_sha: nil); end

    sig { abstract.returns(String) }
    def default_single_commit_message; end

    class AutomatedSuggestionItem
      include SuggestionItem

      sig { params(comment: AutomatedReviewComment).void }
      def initialize(comment)
        @comment = comment
      end

      sig { override.params(pull_request: PullRequest).void }
      def validate!(pull_request)
        unless @comment.pull_request_id == pull_request.id
          raise AutomatedReviewComment::UnprocessableError.new("Comment #{@comment.id} does not belong to pull request #{pull_request.id}")
        end
        if @comment.suggestion.nil?
          raise AutomatedReviewComment::UnprocessableError.new("Comment #{@comment.id} has no suggestion")
        end
        unless @comment.suggestion_state == "suggestion_state_present"
          raise AutomatedReviewComment::UnprocessableError.new("Comment #{@comment.id} suggestion is not in present state")
        end
      end

      sig { override.returns(T::Array[GitHub::Diff::Entry]) }
      def diff_entries
        @comment.suggestion&.diff_entries || []
      end

      sig { override.returns(T.nilable(String)) }
      def co_author_trailer
        email = @comment.pull_request_review_comment&.user&.git_author_email
        return nil if email.nil?
        "Co-authored-by: Copilot Autofix powered by AI <#{email}>"
      end

      sig { override.returns(T.nilable(Repository)) }
      def repository
        @comment.repository
      end

      sig { override.params(user: User, pull_request: PullRequest, commit_sha: T.nilable(String)).void }
      def on_applied(user:, pull_request:, commit_sha: nil)
        @comment.suggestion_state_applied!
        @comment.send(:evaluator)&.apply_suggestion(comment: @comment, user: user, pull: pull_request)

        pr_review_comment = @comment.pull_request_review_comment
        return unless pr_review_comment

        repository = pull_request.head_repository || pull_request.repository
        return unless repository

        file_path = pr_review_comment.path
        GlobalInstrumenter.instrument("suggested_change.applied",
          repository: repository,
          repository_owner: repository.owner,
          pull_request: pull_request,
          comment: pr_review_comment,
          actor: user,
          issue: pull_request.issue,
          file_extension: file_path&.split(".")&.last,
          error: nil,
          commit_sha: commit_sha,
        )
      end

      sig { override.returns(String) }
      def default_single_commit_message
        msg = "Potential fix for pull request finding"
        msg += ": #{@comment.title}" if @comment.title.present?
        msg
      end
    end

    class UserSuggestionItem
      include SuggestionItem

      sig { params(comment: PullRequestReviewComment, suggestion_index: Integer).void }
      def initialize(comment, suggestion_index)
        @comment = comment
        @suggestion_index = suggestion_index
      end

      # Validates that the comment is in a state where its suggestion can be applied.
      # These checks mirror PullRequestReviewComment::ApplySuggestedChange#validate_applicable_suggested_changes!
      # in packages/pull_requests/app/models/pull_request_review_comment/apply_suggested_change.rb.
      sig { override.params(pull_request: PullRequest).void }
      def validate!(pull_request)
        unless @comment.pull_request_id == pull_request.id
          GitHub.logger.warn("UserSuggestionItem validation failed: PR mismatch", "gh.pull_request.comment.id": @comment.id, "gh.pull_request.id": pull_request.id)
          raise AutomatedReviewComment::ValidationError.new("Comment #{@comment.id} does not belong to pull request #{pull_request.id}")
        end
        unless @comment.body_may_contain_suggestion?
          GitHub.logger.warn("UserSuggestionItem validation failed: no suggestion in body", "gh.pull_request.comment.id": @comment.id)
          raise AutomatedReviewComment::ValidationError.new("Comment #{@comment.id} does not contain a suggestion")
        end

        # Match the outdated check which uses latest_positioning when the
        # prx_comment_outside_the_diff feature flag is enabled.
        thread = @comment.pull_request_review_thread
        if thread.nil?
          raise AutomatedReviewComment::InvalidDataError.new("Comment #{@comment.id} does not have an associated review thread")
        end

        repo = pull_request.repository
        thread_outdated = if repo&.feature_flag_enabled?(:prx_comment_outside_the_diff, default: false) || repo&.owner&.feature_flag_enabled?(:prx_comment_outside_the_diff, default: false)
          case thread.latest_positioning
          when nil
            thread.outdated?
          when PullRequests::CommentPosition::Positions::Indeterminate, PullRequests::CommentPosition::Positions::Errored
            true
          else
            false
          end
        else
          thread.outdated?
        end

        if thread_outdated
          GitHub.logger.warn("UserSuggestionItem validation failed: comment outdated", "gh.pull_request.comment.id": @comment.id)
          raise AutomatedReviewComment::ValidationError.new("Comment #{@comment.id} is outdated and cannot be applied")
        end

        if thread.on_file?
          GitHub.logger.warn("UserSuggestionItem validation failed: file-level comment", "gh.pull_request.comment.id": @comment.id)
          raise AutomatedReviewComment::ValidationError.new("Applying suggestions on file-level comments is not supported")
        end

        if @comment.pending?
          GitHub.logger.warn("UserSuggestionItem validation failed: pending review", "gh.pull_request.comment.id": @comment.id)
          raise AutomatedReviewComment::ValidationError.new("Suggestions cannot be applied on pending reviews")
        end

        if thread.selection_contains_deletions?
          GitHub.logger.warn("UserSuggestionItem validation failed: selection contains deletions", "gh.pull_request.comment.id": @comment.id)
          raise AutomatedReviewComment::ValidationError.new("Applying suggestions on deleted lines is not supported")
        end
      end

      sig { override.returns(T::Array[GitHub::Diff::Entry]) }
      def diff_entries
        ReviewComments::UserCommentSuggestion.build_diff_entries(
          comment: @comment,
          suggestion_index: @suggestion_index
        )
      rescue ReviewComments::UserCommentSuggestion::ParseError => e
        raise AutomatedReviewComment::InvalidDataError.new(e.message)
      rescue ReviewComments::UserCommentSuggestion::InvalidIndexError => e
        GitHub.logger.warn("UserSuggestionItem diff_entries failed: invalid suggestion index", "gh.pull_request.comment.id": @comment.id, exception: e)
        raise AutomatedReviewComment::UnprocessableError.new(e.message)
      end

      # Follows the same byline pattern as ApplySuggestedChange#byline
      sig { override.returns(T.nilable(String)) }
      def co_author_trailer
        user = @comment.user
        return nil if user.nil?
        author_name, author_email = User.git_author_info(user)
        "Co-authored-by: #{[author_name, "<#{author_email}>"].reject(&:blank?).join(" ")}"
      end

      sig { override.returns(T.nilable(Repository)) }
      def repository
        @comment.repository
      end

      sig { override.params(user: User, pull_request: PullRequest, commit_sha: T.nilable(String)).void }
      def on_applied(user:, pull_request:, commit_sha: nil)
        thread = @comment.pull_request_review_thread
        thread&.resolve(resolver: user) unless thread&.resolved?

        repository = pull_request.head_repository || pull_request.repository
        return unless repository

        file_path = @comment.path
        GlobalInstrumenter.instrument("suggested_change.applied",
          repository: repository,
          repository_owner: repository.owner,
          pull_request: pull_request,
          comment: @comment,
          actor: user,
          issue: pull_request.issue,
          file_extension: file_path&.split(".")&.last,
          error: nil,
          commit_sha: commit_sha,
        )
      end

      sig { override.returns(String) }
      def default_single_commit_message
        "Apply suggestion from code review"
      end
    end
  end
end
