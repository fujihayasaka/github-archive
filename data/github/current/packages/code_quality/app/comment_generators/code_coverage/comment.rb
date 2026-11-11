# typed: strict
# frozen_string_literal: true

# Generates the Markdown/HTML body for a code coverage PR comment.
# Receives the decoded Hydro message overview along with repo/PR metadata
# and renders the comment via an ERB template.
module CodeCoverage
  class Comment
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::UrlHelper

    TEMPLATE_PATH = T.let(
      Rails.root.join("packages", "code_quality", "app", "comment_generators", "templates", "comment.text.erb").to_s,
      String,
    )

    MAX_BRANCH_NAME_LENGTH = T.let(20, Integer)
    MAX_FILE_PATH_LENGTH = T.let(30, Integer)
    FILE_COLUMN_WIDTH_PX = T.let(300, Integer)
    NO_DATA_MARKER = T.let("\u2014", String)

    sig do
      params(
        overview: T::Hash[Symbol, T.untyped],
        repository: Repository,
        pull_request: PullRequest,
        updated: T::Boolean,
      ).void
    end
    def initialize(overview:, repository:, pull_request:, updated: false)
      @overview = overview
      @repository = repository
      @pull_request = pull_request
      @updated = updated
    end

    sig { returns(String) }
    def body
      ERB.new(File.read(TEMPLATE_PATH), trim_mode: "-").result(binding)
    end

    private

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def categories
      raw = @overview[:categories] || []
      raw.map do |cat|
        cat.merge(sorted_files: sorted_files(cat))
      end
    end

    sig { returns(String) }
    def head_sha
      @overview[:head_commit_sha].to_s
    end

    sig { returns(T::Array[String]) }
    def languages
      (categories.map { |c| c[:language_name] }.uniq.compact.select(&:present?))
    end

    sig { returns(String) }
    def base_branch_link
      branch_link(base_ref)
    end

    sig { returns(String) }
    def head_branch_link
      branch_link(head_ref)
    end

    sig { params(ref: String).returns(String) }
    def branch_link(ref)
      link_to(truncate_ref(ref), "/#{name_with_display_owner}/tree/#{ref}", id: "cc-branch", title: "#{name_with_display_owner}:#{ref}")
    end

    sig { params(sha: String).returns(String) }
    def commit_sha_label(sha)
      content_tag(:span, sha[0, 7], id: "cc-sha")
    end

    sig { params(ref: String).returns(String) }
    def truncate_ref(ref)
      if ref.length > MAX_BRANCH_NAME_LENGTH
        "#{ref[0, MAX_BRANCH_NAME_LENGTH]}..."
      else
        ref
      end
    end

    sig { params(path: String).returns(String) }
    def truncate_file_path(path)
      return path if path.length <= MAX_FILE_PATH_LENGTH

      half_len = MAX_FILE_PATH_LENGTH / 2

      "#{path[0, half_len]}...#{path[-half_len, half_len]}"
    end

    sig { params(path: String).returns(String) }
    def file_label(path)
      truncated = truncate_file_path(path)
      code = content_tag(:code, truncated)
      if truncated != path
        content_tag(:span, code, title: path)
      else
        code
      end
    end

    sig { params(category: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def base_data_available?(category)
      category[:base_commit_sha].present?
    end

    sig { params(category: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def coverage_unchanged?(category)
      base_data_available?(category) &&
        category[:base_ref_coverage].to_i == category[:head_ref_coverage].to_i
    end

    sig { params(category: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def no_coverage_changes?(category)
      coverage_unchanged?(category) && !files_have_coverage_changes?(category)
    end

    sig { params(category: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def files_have_coverage_changes?(category)
      files = category[:files]
      return false if files.empty?

      files.any? { |f| f[:head_file_coverage].to_i != f[:base_file_coverage].to_i }
    end

    sig { params(category: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def show_file_table?(category)
      return false if sorted_files(category).blank?
      return true unless coverage_unchanged?(category)

      files_have_coverage_changes?(category)
    end

    sig { params(value: T.untyped, category: T::Hash[Symbol, T.untyped]).returns(String) }
    def format_coverage(value, category)
      return NO_DATA_MARKER unless base_data_available?(category)

      "#{value.to_i}%"
    end

    sig { params(diff: Integer, category: T::Hash[Symbol, T.untyped]).returns(String) }
    def format_diff(diff, category)
      return NO_DATA_MARKER unless base_data_available?(category)

      if diff > 0
        "+#{diff}%"
      elsif diff < 0
        "#{diff}%"
      else
        "0%"
      end
    end

    sig { params(category: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def sorted_files(category)
      files = category[:files]
      return [] if files.blank?

      if base_data_available?(category)
        files.sort_by { |f| f[:head_file_coverage].to_i - f[:base_file_coverage].to_i }
      else
        files.sort_by { |f| -f[:head_file_coverage].to_i }
      end
    end

    sig { returns(String) }
    def name_with_display_owner
      @repository.name_with_display_owner
    end

    sig { returns(String) }
    def base_ref
      @pull_request.base_ref
    end

    sig { returns(String) }
    def head_ref
      @pull_request.head_ref
    end

    sig { returns(Integer) }
    def pr_number
      @pull_request.number
    end

    sig { returns(T::Boolean) }
    def updated?
      @updated
    end

    STAFFSHIP_ORGS = T.let(%w[github octodemo].freeze, T::Array[String])

    sig { returns(String) }
    def footer
      if STAFFSHIP_ORGS.include?(@repository.owner_display_login)
        "Code Coverage report on PRs is in staff-ship. [Learn more and provide us with your feedback](https://github.com/github/security-products/discussions/2139)."
      elsif FeatureFlag.vexi.enabled?(:code_coverage_public_preview, @repository.owner, default: false)
        "Code Coverage is in Public Preview. [Learn more and provide us with your feedback](https://github.com/orgs/community/discussions/194833)."
      else
        "Code Coverage is in Private Preview. [Learn more and provide us with your feedback](https://github.com/orgs/community/discussions/191787)."
      end
    end

    sig { params(category: T::Hash[Symbol, T.untyped]).returns(ActiveSupport::SafeBuffer) }
    def category_heading(category)
      content_tag(:h4) do
        [category[:language_name], category[:label]].reject(&:blank?).join(" / ")
      end
    end
  end
end
