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

    PR_OVERVIEW_HEADER = "## Pull Request Overview"

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
    def summary
      format_summary(raw_summary)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def raw_summary
      @raw_summary ||= begin
        summary_data = T.let({}, T::Hash[T.untyped, T.untyped])
        @model_response[:copilot_references].each do |ref|
          if ref[:type] == "github.pull-request-summary"
            summary_data = ref[:data]
            break
          end
        end
        summary_data
      end
    end

    sig { returns(String) }
    def review_summary
      "Copilot reviewed #{files_changed_count - excluded_files.size} out of #{files_changed_count} changed files in this pull request and generated #{comments_text}."
    end

    def summary_present?
      raw_summary[:overall_summary].present? && raw_summary[:per_file_summary].present?
    end

    sig { params(data: T::Hash[T.untyped, T.untyped]).returns(String) }
    def format_summary(data)
      unless summary_present?
        return ""
      end

      overall_summary = data[:overall_summary]
      per_file_summary = data[:per_file_summary]

      files_count = count_table_lines(per_file_summary)

      if files_count < 2
        "#{PR_OVERVIEW_HEADER}\n\n" + overall_summary
      elsif files_count > 4
        per_file_summary = per_file_summary.gsub("\n", "\r\n")
        <<~LONG_SUMMARY
        #{PR_OVERVIEW_HEADER}

        #{overall_summary}

        ### Reviewed Changes

        #{review_summary}

        <details>
        <summary>Show a summary per file</summary>

        #{per_file_summary}
        </details>
        LONG_SUMMARY
      else
        "#{PR_OVERVIEW_HEADER}\n\n" + overall_summary + "\n\n### Reviewed Changes\n\n" + review_summary + "\n\n" + per_file_summary
      end
    end

    def count_table_lines(markdown_table)
      lines = markdown_table.split("\n")
      table_lines = lines.select { |line| line.match(/^\|.*\|$/) }
      table_lines.count - 2
    end

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
      if summary_present?
        <<~MSG
        #{summary}

        #{list_excluded_files}
        #{list_excluded_comments}
        MSG
      else
        <<~MSG
        #{summary}

        #{review_summary}

        #{list_excluded_files}
        #{list_excluded_comments}
        MSG
      end
    end

    def comments_text
      if @comments.any?
        "#{@comments.size} #{"comment".pluralize(@comments.size)}"
      else
        "no comments"
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
      <summary>Comments suppressed due to low confidence (#{excluded_comments.size})</summary>

      #{comment_list}
      </details>
      EXCLUDED_COMMENTS
    end
  end
end
