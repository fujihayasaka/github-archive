# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::RichDiff
  class Loader
    include UrlHelper

    class FileRendererBlobData < T::Struct
      const :identity_uuid, String
      const :size, Integer
      const :type, String
      const :url, String
    end

    class Data < T::Struct
      const :can_toggle_rich_diff, T::Boolean
      const :default_to_rich_diff, T::Boolean
      const :prose_diff_html, T.nilable(String)
      const :render_info, T.nilable(FileRendererBlobData)
      const :dependency_diff_path, T.nilable(String)
    end

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        binary_sizes: T::Hash[String, Integer],
        skip_dependency_review: T::Boolean,
        repository: Repository,
        force_load_rich_diff: T::Boolean,
        current_user: T.nilable(User),
        old_tree_entry: T.nilable(TreeEntry),
        new_tree_entry: T.nilable(TreeEntry),
        short_path: T.nilable(String),
      ).returns(Data)
    end
    def self.load(diff_entry:, binary_sizes:, skip_dependency_review:, repository:, force_load_rich_diff:, current_user: nil, old_tree_entry: nil, new_tree_entry: nil, short_path: nil)
      new(diff_entry:, binary_sizes:, skip_dependency_review:, repository:, force_load_rich_diff:, current_user:, old_tree_entry:, new_tree_entry:, short_path:).load
    end

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        binary_sizes: T::Hash[String, Integer],
        skip_dependency_review: T::Boolean,
        repository: Repository,
        force_load_rich_diff: T::Boolean,
        current_user: T.nilable(User),
        old_tree_entry: T.nilable(TreeEntry),
        new_tree_entry: T.nilable(TreeEntry),
        short_path: T.nilable(String),
      ).void
    end
    def initialize(diff_entry:, binary_sizes:, skip_dependency_review:, repository:, force_load_rich_diff:, current_user:, old_tree_entry:, new_tree_entry:, short_path:)
      @repository = repository
      @diff_entry = diff_entry
      @current_user = current_user
      @old_tree_entry = old_tree_entry
      @new_tree_entry = new_tree_entry
      @binary_sizes = binary_sizes
      @skip_dependency_review = skip_dependency_review
      @short_path = short_path
      @force_load_rich_diff = force_load_rich_diff
    end

    sig { returns(Data) }
    def load
      diff_entry_blob = @diff_entry.deleted? ? @old_tree_entry : @new_tree_entry
      code_rendering_service = CodeRenderingService.for(diff_entry_blob, :diff, @current_user, @repository, diff: @diff_entry)

      decider = PullRequests::PageData::Diffs::RichDiff::Decider.new(
        diff_entry: @diff_entry,
        diff_entry_blob: diff_entry_blob,
        code_rendering_service: code_rendering_service,
        short_path: @short_path,
        skip_dependency_review: @skip_dependency_review
      )

      if decider.is_rich_diff && (decider.default_to_rich_diff || @force_load_rich_diff)
        renderer = PullRequests::PageData::Diffs::RichDiff::Renderer.new(
          diff_entry: @diff_entry,
          repository: @repository,
          code_rendering_service: code_rendering_service,
          old_tree_entry: @old_tree_entry,
          new_tree_entry: @new_tree_entry,
          binary_sizes: @binary_sizes
        )

        if decider.is_prose_diff?
          diff_html = renderer.prose_diff_html
        else
          render_info = renderer.rendered_blob
        end
      end

      if decider.is_rich_diff && decider.dependency_review_diff?
        dependency_diff_path = Rails.application.routes.url_helpers.dependency_review_rich_diff_path(
          repository: @repository,
          user_id: @repository.owner_display_login,
          head_sha: @diff_entry.b_sha,
          base_sha: @diff_entry.a_sha,
          manifest_path: @diff_entry.path
        )
      end

      Data.new(
        can_toggle_rich_diff: decider.is_rich_diff && decider.toggleable?,
        dependency_diff_path: dependency_diff_path,
        default_to_rich_diff: decider.default_to_rich_diff,
        prose_diff_html: diff_html,
        render_info: render_info,
      )
    end
  end
end
