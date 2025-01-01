# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class ReviewBodyMessageGenerator
    NO_FILES_BODY = "Copilot wasn't able to review any files in this pull request."
    EXCLUDE_REASON_MAP = {
      file_type_not_supported: "Language not supported",
      below_top_k: "Evaluated as low risk",
      file_too_big: "File too large"
    }.freeze

    sig { params(pull: PullRequest, repo: Repository, comments: T::Array[T::Hash[T.untyped, T.untyped]], model_response: T.any(T.untyped, T.untyped), requestor: User).void }
    def initialize(pull:, repo:, comments:, model_response:, requestor:)
      @pull = pull
      @repo = repo
      @comments = comments
      @model_response = model_response
      @requestor = requestor
    end

    sig { returns(T.nilable(String)) }
    def create
      body = T.let("", String)

      body = if excluded_files.size == files_changed_count
        no_files_reviewed_message
      else
        review_body_summary
      end

      if @requestor.feature_enabled?(:copilot_code_review_show_comment_body_tips)
        body += body_message_tip
      end

      body
    end

    private

    sig { returns(String) }
    def body_message_tip
      CodeReviewBodyMessageTipGenerator.tip_for(@pull, @repo, @comments)
    end

    sig { returns(String) }
    def no_files_reviewed_message
      <<~MSG
      #{NO_FILES_BODY}
      #{list_excluded_files}
      MSG
    end

    sig { returns(String) }
    def review_body_summary
      <<~MSG
      Copilot reviewed #{files_changed_count - excluded_files.size} out of #{files_changed_count} changed files in this pull request and generated #{suggestions_text}.
      #{list_excluded_files}
      #{list_excluded_comments}
      MSG
    end

    def suggestions_text
      if @comments.any?
        "#{@comments.size} #{"suggestion".pluralize(@comments.size)}"
      else
        "no suggestions"
      end
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def excluded_comments
      return @excluded_comments if defined?(@excluded_comments)
      @excluded_comments = @model_response[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.excluded-pull-request-comment"

        # path, line, body, side
        ref[:data]
      end
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def excluded_files
      return @excluded_files if defined?(@excluded_files)
      @excluded_files = @model_response[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.excluded-file"

        # filepath, language, reason
        ref[:data]
      end
    end

    sig { returns(Numeric) }
    def files_changed_count
      return @files_changed_count if defined?(@files_changed_count)
      @files_changed_count = @pull.changed_files
    end

    sig { returns(String) }
    def list_excluded_files
      return "" if excluded_files.empty?

      file_list = excluded_files.map do |file|
        "* **#{file[:file_path]}**: #{EXCLUDE_REASON_MAP[file[:reason].to_sym]}"
      end.join("\n")

      <<~EXCLUDED_FILES
      <details>
      <summary>Files not reviewed (#{excluded_files.size})</summary>

      #{file_list}
      </details>
      EXCLUDED_FILES
    end

    sig { returns(String) }
    def list_excluded_comments
      return "" if excluded_comments.empty?

      comment_list = excluded_comments.map do |comment|
        line_contents = "```\n#{comment[:line_content]}\n```"
        comment_body = T.let(String.new, String)
        comment_body << "**#{comment[:path]}:#{comment[:line]}**\n"
        comment_body << "* #{comment[:body]}\n"
        comment_body << line_contents if comment[:line_content].present?
      end.join("\n")

      <<~EXCLUDED_COMMENTS
      <details>
      <summary>Comments skipped due to low confidence (#{excluded_comments.size})</summary>

      #{comment_list}
      </details>
      EXCLUDED_COMMENTS
    end
  end
end
