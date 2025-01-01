# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::RichDiff
  # This class encapsulates all the logic used for determining
  # rendering either prose (ie - markdown) or renderable rich diffs
  # It works together in tandem with the Decider class
  class Renderer
    include BlobMarkupHelper
    include FailbotHelper
    include TextHelper
    include UrlHelper

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        repository: Repository,
        code_rendering_service: CodeRenderingService::DiffComponent,
        old_tree_entry: T.nilable(TreeEntry),
        new_tree_entry: T.nilable(TreeEntry),
        binary_sizes: T::Hash[String, Integer],
      ).void
    end
    def initialize(diff_entry:, repository:, code_rendering_service:, old_tree_entry:, new_tree_entry:, binary_sizes:)
      @diff_entry = diff_entry
      @repository = repository
      @code_rendering_service = code_rendering_service
      @old_tree_entry = old_tree_entry
      @new_tree_entry = new_tree_entry
      @binary_sizes = binary_sizes
    end

    sig { returns(T.nilable(String)) }
    def prose_diff_html
      if @diff_entry.added?
        before_html = ActiveSupport::SafeBuffer.new("")
      elsif @old_tree_entry
        before_html = with_failbot_rescue("gh.repo.path": @diff_entry.path, "gh.diff.type": "before_html") do
          markup_blob_content_if_successful(@old_tree_entry, path: @old_tree_entry.path, sanitize_orphan_hrefs: true)
        end
      end

      if @diff_entry.deleted?
        after_html = ActiveSupport::SafeBuffer.new("")
      elsif @new_tree_entry
        after_html = with_failbot_rescue("gh.repo.path": @diff_entry.path, "gh.diff.type": "after_html") do
          markup_blob_content_if_successful(@new_tree_entry, path: @new_tree_entry.path, sanitize_orphan_hrefs: true)
        end
      end

      if before_html && after_html
        html_diff = with_failbot_rescue("gh.repo.path": @diff_entry.path, "gh.diff.type": "@html_diff") do
          GitHub.instrument "prose-diff.render", diff: @diff_entry, repository: @repository do
            GitHub::HTML::Diff.new(before_html, after_html)
          end
        end
      end

      if html_diff
        html = with_failbot_rescue("gh.repo.path": @diff_entry.path, "gh.diff.type": "diff_html") do
          formatted_blob_content(html_diff.html)
        end
      end

      html
    end

    sig { returns(T.nilable(Loader::FileRendererBlobData)) }
    def rendered_blob
      Loader::FileRendererBlobData.new(
        identity_uuid: @code_rendering_service.identity,
        size: @binary_sizes[@diff_entry.b_blob] || 0,
        type: @code_rendering_service.render_type&.to_s || "",
        # we don't have a file_view or file_list_view to work with
        # but it seems optional and only used for size parameters - will ship as is and evaluate
        url: @code_rendering_service.rich_diff_url(file_view: nil, file_list_view: nil).to_s || "",
      )
    end

    private

    sig { params(additional: T::Hash[T.untyped, T.untyped], block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def with_failbot_rescue(additional = {}, &block)
      yield
    rescue StandardError => e # rubocop:todo Lint/RescueException
      failbot(e, { app: "github-diff" }.merge(additional))
      nil
    end
  end
end
