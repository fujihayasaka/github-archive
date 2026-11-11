# typed: true
# frozen_string_literal: true

module PullRequests::Copilot
  class ReviewBodyMessageGenerator
    include GitHub::Memoizer

    NO_FILES_BODY = "Copilot wasn't able to review any files in this pull request."
    EXCLUDE_REASON_MAP = {
      file_type_not_supported: "File type not supported",
      generated_file: "Generated file",
      below_top_k: "Evaluated as low risk",
      file_too_big: "File too large"
    }.freeze

    PR_OVERVIEW_HEADER = "## Pull request overview"

    # Shown at the top of the review body when only some of the changed files
    # are excluded by Copilot content exclusion policy. The all-files-excluded
    # case is handled upstream via REASON_CONTENT_EXCLUDED in CodeReviewCreator.
    # github/copilot-code-review#962
    PARTIAL_CONTENT_EXCLUSION_WARNING = "Copilot's review of this pull request may be incomplete because some of the changed files are excluded by your Copilot content exclusion settings. See [Excluding content from Copilot](https://docs.github.com/en/copilot/how-tos/configure-content-exclusion/exclude-content-from-copilot) for details."

    sig do
      params(
        pull: PullRequest,
        repo: Repository,
        comments: T::Array[T::Hash[T.untyped, T.untyped]],
        model_response: T.any(T.untyped, T.untyped),
        requestor: User,
        ref_data: T::Hash[T.untyped, T.untyped],
        has_previous_reviews: T::Boolean,
        assessment_message: T.nilable(String),
        assessment_feedback_note: T.nilable(String),
        collapse_pr_overview: T::Boolean,
      ).void
    end
    def initialize(pull:, repo:, comments:, model_response:, requestor:, ref_data:, has_previous_reviews: false, assessment_message: nil, assessment_feedback_note: nil, collapse_pr_overview: false)
      @pull = pull
      @repo = repo
      @comments = comments
      @model_response = model_response
      @requestor = requestor
      @ref_data = ref_data
      @has_previous_reviews = has_previous_reviews
      @assessment_message = assessment_message
      @assessment_feedback_note = assessment_feedback_note
      @collapse_pr_overview = collapse_pr_overview
    end

    sig { returns(T.nilable(String)) }
    def create
      if @collapse_pr_overview
        body = inline_approval_readiness_body
        body += formatted_footnote_content if copilot_footnote_content.present?

        return body
      end

      body = if excluded_files.size == files_reviewed_count
        no_files_reviewed_message
      else
        warnings_block + review_body_summary
      end
      body = "#{@assessment_message}\n\n#{body}" if @assessment_message.present?
      body += formatted_footnote_content if copilot_footnote_content.present?

      body
    end

    private

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :ref_data

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
      total_reviewed_files = files_reviewed_count - excluded_files.size
      if refresh_overview_enabled?
        cta = custom_instructions_cta
        heading = "## Copilot's findings"
        findings_header = cta.present? ? "#{heading}\n\n#{cta}" : heading

        <<~MSG
        #{findings_header}

        #{list_excluded_files}
        #{list_content_exclusion_files}
        #{list_excluded_comments}

        - **Files reviewed:** #{total_reviewed_files}/#{files_changed_count} changed files
        - **Comments generated:** #{comments_count_label}
        MSG
      else
        "Copilot reviewed #{total_reviewed_files} out of #{files_changed_count} changed files in this pull request and generated #{comments_text}."
      end
    end

    sig { returns(String) }
    def inline_approval_readiness_body
      parts = T.let([], T::Array[String])

      parts << @assessment_message.to_s if @assessment_message.present?
      parts << warnings_block.strip if warning_messages.any?

      if summary_present? && !@has_previous_reviews
        parts << collapsible_section("Pull request overview", raw_summary[:overall_summary].to_s.strip)
        parts << collapsible_section("File summaries", inline_file_summaries)
      else
        parts << collapsible_section("Copilot's findings", review_coverage)
      end

      parts << @assessment_feedback_note.to_s.strip if @assessment_feedback_note.present?

      parts.compact_blank.join("\n\n")
    end

    sig { returns(String) }
    def inline_file_summaries
      parts = T.let([], T::Array[String])

      parts << raw_summary[:per_file_summary].to_s.gsub("\n", "\r\n").strip

      parts << <<~COVERAGE.strip
        ### Copilot's findings

        #{review_coverage}
      COVERAGE

      parts.compact_blank.join("\n\n")
    end

    sig { returns(String) }
    def review_coverage
      total_reviewed_files = files_reviewed_count - excluded_files.size
      parts = T.let([], T::Array[String])

      if excluded_files.size == files_reviewed_count
        parts << NO_FILES_BODY
      end

      parts << inline_list_excluded_files
      parts << inline_list_content_exclusion_files
      parts << inline_list_excluded_comments
      parts << <<~MSG.strip
        - **Files reviewed:** #{total_reviewed_files}/#{files_changed_count} changed files
        - **Comments generated:** #{comments_count_label}
      MSG

      parts.compact_blank.join("\n\n")
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

      if refresh_overview_enabled?
        if @has_previous_reviews
          return review_summary
        end
        return format_refresh_overview(overall_summary, per_file_summary, files_count)
      end

      if @has_previous_reviews
        "#{PR_OVERVIEW_HEADER}\n\n" + review_summary
      elsif files_count < 2
        "#{PR_OVERVIEW_HEADER}\n\n" + overall_summary
      elsif files_count > 4
        per_file_summary = per_file_summary.gsub("\n", "\r\n")
        <<~LONG_SUMMARY
        #{PR_OVERVIEW_HEADER}

        #{overall_summary}

        ### Reviewed changes

        #{review_summary}

        <details>
        <summary>Show a summary per file</summary>

        #{per_file_summary}
        </details>
        LONG_SUMMARY
      else
        "#{PR_OVERVIEW_HEADER}\n\n" + overall_summary + "\n\n### Reviewed changes\n\n" + review_summary + "\n\n" + per_file_summary
      end
    end

    sig { params(overall_summary: String, per_file_summary: String, files_count: Integer).returns(String) }
    def format_refresh_overview(overall_summary, per_file_summary, files_count)
      per_file_summary = per_file_summary.gsub("\n", "\r\n")
      per_file_summary_open = files_count < 5 ? " open" : ""

      <<~SUMMARY
      #{PR_OVERVIEW_HEADER}

      #{overall_summary}

      <details#{per_file_summary_open}>
      <summary>Show a summary per file</summary>

      #{per_file_summary}
      </details>

      #{review_summary}
      SUMMARY
    end

    def count_table_lines(markdown_table)
      lines = markdown_table.split("\n")
      table_lines = lines.select { |line| line.match(/^\|.*\|$/) }
      table_lines.count - 2
    end

    sig { returns(String) }
    def no_files_reviewed_message
      <<~MSG
      #{NO_FILES_BODY}
      #{list_excluded_files}
      #{list_content_exclusion_files}
      MSG
    end

    sig { returns(String) }
    def review_body_summary
      if refresh_overview_enabled?
        body = summary_present? ? summary : review_summary
        <<~MSG
        #{body}
        MSG
      elsif summary_present?
        <<~MSG
        #{summary}

        #{list_excluded_files}
        #{list_content_exclusion_files}
        #{list_excluded_comments}
        MSG
      else
        <<~MSG
        #{summary}

        #{review_summary}

        #{list_excluded_files}
        #{list_content_exclusion_files}
        #{list_excluded_comments}
        MSG
      end
    end

    sig { params(summary: String, content: String).returns(String) }
    def collapsible_section(summary, content)
      <<~MSG.strip
      <details>
      <summary>#{summary}</summary>

      #{content}
      </details>
      MSG
    end

    sig { returns(String) }
    def comments_text
      if @comments.any?
        "#{@comments.size} #{"comment".pluralize(@comments.size)}"
      elsif @has_previous_reviews
        "no new comments"
      else
        "no comments"
      end
    end

    sig { returns(String) }
    def comments_count_label
      count = @comments.size
      if @has_previous_reviews && count == 0
        "0 new"
      else
        count.to_s
      end
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    memoize def excluded_comments
      @model_response[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.excluded-pull-request-comment"
        next unless ref.dig(:data, :path).in?(changed_files)

        # path, line, body, side
        ref[:data]
      end
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    memoize def excluded_files
      @model_response[:copilot_references].filter_map do |ref|
        next unless ref[:type] == "github.excluded-file"
        next unless ref.dig(:data, :path).in?(changed_files)

        # filepath, language, reason
        ref[:data]
      end
    end

    # Files excluded by Copilot content exclusion policy, as reported by
    # the agent's runtime check. Surfaced via the `github.content-exclusion`
    # reference, with shape `{ excluded_files: ["path1", ...] }`. There is
    # at most one such reference per review.
    #
    # Trusted as-is. We deliberately do not intersect with `changed_files`:
    # dotcom's `DiffsFilter` strips content-excluded paths from the request
    # before CCRA runs (see compare_trees_diff_creator.rb#filtered_diffs),
    # so the agent-reported paths and `changed_files` are disjoint by
    # construction. The diff may have shifted between request and response,
    # but the agent's view is authoritative for the review it just produced.
    # github/copilot-code-review#962
    sig { returns(T::Array[String]) }
    memoize def content_excluded_files
      @model_response[:copilot_references].each do |ref|
        next unless ref[:type] == "github.content-exclusion"
        return Array.wrap(ref.dig(:data, :excluded_files))
      end
      []
    end

    sig { returns(Integer) }
    memoize def files_reviewed_count
      changed_files.size
    end

    sig { returns(T::Set[String]) }
    memoize def changed_files
      Array.wrap(ref_data[:files]).to_set { |f| f[:fileName] }
    end

    sig { returns(Numeric) }
    memoize def files_changed_count
      @pull.changed_files
    end

    sig { returns(String) }
    def list_excluded_files
      return "" if excluded_files.empty?

      file_list = excluded_files.map do |file|
        reason = EXCLUDE_REASON_MAP[file[:exclusion_reason]&.to_sym] || "Not reviewed"
        "* **#{file[:path]}**: #{reason}"
      end.join("\n")

      <<~EXCLUDED_FILES
      <details>
      <summary>Files not reviewed (#{excluded_files.size})</summary>

      #{file_list}
      </details>
      EXCLUDED_FILES
    end

    sig { returns(String) }
    def inline_list_excluded_files
      return "" if excluded_files.empty?

      file_list = excluded_files.map do |file|
        reason = EXCLUDE_REASON_MAP[file[:exclusion_reason]&.to_sym] || "Not reviewed"
        "* **#{file[:path]}**: #{reason}"
      end.join("\n")

      <<~EXCLUDED_FILES.strip
      ### Files not reviewed (#{excluded_files.size})

      #{file_list}
      EXCLUDED_FILES
    end

    sig { returns(String) }
    def list_content_exclusion_files
      return "" if content_excluded_files.empty?

      file_list = content_excluded_files.map do |path|
        "* **#{path}**"
      end.join("\n")

      <<~CONTENT_EXCLUSION_FILES
      <details>
      <summary>Files excluded by content exclusion policy (#{content_excluded_files.size})</summary>

      #{file_list}
      </details>
      CONTENT_EXCLUSION_FILES
    end

    sig { returns(String) }
    def inline_list_content_exclusion_files
      return "" if content_excluded_files.empty?

      file_list = content_excluded_files.map do |path|
        "* **#{path}**"
      end.join("\n")

      <<~CONTENT_EXCLUSION_FILES.strip
      ### Files excluded by content exclusion policy (#{content_excluded_files.size})

      #{file_list}
      CONTENT_EXCLUSION_FILES
    end

    sig { returns(String) }
    def list_excluded_comments
      return "" if excluded_comments.empty?

      comment_list = excluded_comments.map do |comment|
        line_contents = "\n```\n#{comment[:line_content]}\n```"
        comment_body = T.let(String.new, String)
        comment_body << "**#{comment[:path]}:#{comment[:line]}**\n"
        comment_body << "* #{comment[:body]}"
        comment_body << line_contents if comment[:line_content].present?

        comment_body
      end.join("\n")

      <<~EXCLUDED_COMMENTS
      <details>
      <summary>Comments suppressed due to low confidence (#{excluded_comments.size})</summary>

      #{comment_list}
      </details>
      EXCLUDED_COMMENTS
    end

    sig { returns(String) }
    def inline_list_excluded_comments
      return "" if excluded_comments.empty?

      comment_list = excluded_comments.map do |comment|
        line_contents = "\n```\n#{comment[:line_content]}\n```"
        comment_body = T.let(String.new, String)
        comment_body << "**#{comment[:path]}:#{comment[:line]}**\n"
        comment_body << "* #{comment[:body]}"
        comment_body << line_contents if comment[:line_content].present?

        comment_body
      end.join("\n")

      <<~EXCLUDED_COMMENTS.strip
      ### Comments suppressed due to low confidence (#{excluded_comments.size})

      #{comment_list}
      EXCLUDED_COMMENTS
    end

    # Aggregates warnings from different sources to surface at the top of the
    # review body. New warning sources should append to the array here so that
    # rendering stays in `warnings_block`.
    sig { returns(T::Array[String]) }
    def warning_messages
      messages = T.let([], T::Array[String])
      # The all-files-content-excluded case short-circuits upstream in CCRA
      # via `REASON_CONTENT_EXCLUDED` and is rendered by CodeReviewCreator,
      # not this generator. Any reference reaching here is, by definition,
      # the partial case.
      messages << PARTIAL_CONTENT_EXCLUSION_WARNING if content_excluded_files.any?
      messages
    end

    # Renders `warning_messages` as a GFM warning alert with one bullet per
    # warning, or an empty string when there are no warnings. Multi-line
    # warnings keep all lines inside the alert via `>   ` continuation.
    sig { returns(String) }
    def warnings_block
      messages = warning_messages
      return "" if messages.empty?

      list = messages.map do |warning|
        first, *rest = warning.to_s.lines(chomp: true)
        (["> - #{first}"] + rest.map { |line| ">   #{line}" }).join("\n")
      end.join("\n")

      "> [!WARNING]\n#{list}\n\n"
    end

    sig { returns(String) }
    def custom_instructions_cta
      # Only surface the "add custom instructions" tip on the first review of
      # a PR. On re-reviews we've already nudged the author once; repeating
      # the tip on every push is noisy.
      return "" if @has_previous_reviews
      return "" unless custom_instructions_enabled_and_no_file?

      escaped_base_ref_name = UrlHelper.escape_branch(@pull.base_ref_name)
      create_file_url = "/#{@repo.owner_display_login}/#{@repo.name}/new/#{escaped_base_ref_name}?filename=.github/instructions/*.instructions.md"
      docs_url = "https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot"

      note_format = refresh_overview_enabled? ? "> [!TIP]\n> " : "💡 "
      custom_instructions_cta_with_prefix(note_format, create_file_url, docs_url)
    end

    sig { returns(String) }
    def footnote_custom_instructions_cta
      return "" if @has_previous_reviews
      return "" unless custom_instructions_enabled_and_no_file?

      escaped_base_ref_name = UrlHelper.escape_branch(@pull.base_ref_name)
      create_file_url = "/#{@repo.owner_display_login}/#{@repo.name}/new/#{escaped_base_ref_name}?filename=.github/instructions/*.instructions.md"
      docs_url = "https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot"

      custom_instructions_cta_with_prefix("💡 ", create_file_url, docs_url)
    end

    sig { params(note_format: String, create_file_url: String, docs_url: String).returns(String) }
    def custom_instructions_cta_with_prefix(note_format, create_file_url, docs_url)
      "#{note_format}<a href=\"#{create_file_url}\" class=\"Link--inTextBlock\" target=\"_blank\" rel=\"noopener noreferrer\">Add Copilot custom instructions</a> for smarter, more guided reviews. <a href=\"#{docs_url}\" class=\"Link--inTextBlock\" target=\"_blank\" rel=\"noopener noreferrer\">Learn how to get started</a>."
    end

    sig { returns(String) }
    def copilot_footnote_content
      content = ""

      if @collapse_pr_overview || !refresh_overview_enabled?
        content += footnote_custom_instructions_cta
      end

      if @requestor.feature_flag_enabled?(:copilot_code_review_feedback_survey, default: false)
        content += "<br><br>" if content.present?
        content += "You can also share your feedback on Copilot code review. [Take the survey](https://www.surveymonkey.com/r/XP6L3XJ)."
      end

      content.html_safe # rubocop:disable Rails/OutputSafety
    end

    def formatted_footnote_content
      return "" if copilot_footnote_content.blank?
      "\n\n---\n\n#{copilot_footnote_content}"
    end

    sig { returns(T::Boolean) }
    def repo_custom_instructions_enabled?
      repo_settings = @repo.copilot_code_review_repository_settings
      repo_settings.nil? || repo_settings.repo_custom_instructions_enabled
    end

    sig { returns(T::Boolean) }
    def copilot_instructions_file_exists?
      base_oid = ref_data[:baseRefOID]
      ::Copilot::CustomInstructions.for_repository(@repo, base_oid).present? ||
        ::Copilot::CustomInstructions.repo_instructions_md_exists?(@repo, base_oid)
    end

    sig { returns(T::Boolean) }
    def refresh_overview_enabled?
      @requestor.feature_flag_enabled?(:ccr_implement_suggestion_refresh_overview, default: false)
    end

    sig { returns(T::Boolean) }
    def custom_instructions_enabled_and_no_file?
      repo_custom_instructions_enabled? && !copilot_instructions_file_exists?
    end
  end
end
