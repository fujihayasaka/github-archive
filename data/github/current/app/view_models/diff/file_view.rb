# typed: true
# frozen_string_literal: true

module Diff
  class FileView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelpers
    include UrlHelper

    attr_reader :diff, :diff_number, :repository, :current_user,
                :show_generated, :hidden_diff_reason, :diff_blob,
                :show_deleted, :blob_a_size, :blob_b_size,
                :user_reviewed_files, :base_sha
    attr_accessor :hidden_render_diff
    alias :hidden_render_diff? :hidden_render_diff
    alias :show_generated? :show_generated
    alias :show_deleted? :show_deleted

    def after_initialize
      @show_generated = false unless defined?(@show_generated)
    end

    def deferred_syntax_url
      return unless a_sha = diff.a_sha
      return unless b_sha = diff.b_sha

      syntax_highlighted_diff_entries_path(
        repository.owner,
        repository,
        "#{a_sha}..#{b_sha}",
        whitespace_ignored: diff.whitespace_ignored,
        base_sha: base_sha,
      )
    end

    def deferred_syntax_inputs
      {
        # NOTE: this is intentionally the opposite order to the
        # GitHub::Diff::Entry#path method. The logic in
        # GitHub::Diff#requested_deltas assumes that the paths given
        # to filter on are old paths not new paths. Without this reversal
        # we are unable to highlight renamed files.
        path: diff.a_path || diff.b_path
      }
    end

    def path
      diff.path
    end

    def reviewed?(pull)
      file_review_view(pull).reviewed?
    end

    def dismissed?(pull)
      file_review_view(pull).dismissed?
    end

    def file_review_view(pull)
      @file_review_view ||= FileReviewView.new(
        pull_request: pull,
        path: diff.path,
        user: current_user,
        user_reviewed_files: user_reviewed_files
      )
    end

    def has_content?
      hidden_diff_reason.blank? && !diff.text.blank?
    end

    def diff_blob # rubocop:disable Lint/DuplicateMethods
      @diff_blob ||= helpers.diff_blob(diff, repository)
    end

    def code_rendering_service
      return @code_rendering_service if defined?(@code_rendering_service)
      @code_rendering_service = CodeRenderingService.for(diff_blob, :diff, current_user, repository, diff: diff)
    end

    def is_notebook?
      code_rendering_service.is_notebook?
    end

    def diff_head_blob_size
      blob_b_size || 0
    end

    def diff_base_blob_size
      blob_a_size || 0
    end

    def set_diff_blob_sizes(file_list_view)
      # avoid recalculation when unnecessary
      if !file_list_view.blob_sizes.key?(diff.a_blob) ||
         !file_list_view.blob_sizes.key?(diff.b_blob)
        file_list_view.prepare_blob_sizes([diff])
      end
      @blob_a_size = file_list_view.blob_sizes[diff.a_blob]
      @blob_b_size = file_list_view.blob_sizes[diff.b_blob]
    end

    def diff_blob_path(base, head)
      if diff.deleted?
        "/#{base.name_with_display_owner}/blob/#{diff.a_sha}/#{urls.escape_url_branch(diff.a_path)}"
      else
        "/#{head.name_with_display_owner}/blob/#{diff.b_sha}/#{urls.escape_url_branch(diff.b_path)}"
      end
    end

    def display_diff_blob_action_buttons?
      diff.a_sha.present? && !diff.submodule?
    end

    def identifier
      return @identifier if defined?(@identifier)
      @identifier = Digest::SHA256.hexdigest(path)
    end

    def anchor
      @anchor ||= diff_file_anchor(path)
    end

    def show_full_diff_bar?
      diff.binary? || (diff.changes == 0 && !diff.renamed?)
    end

    def simple_rename?
      diff.renamed? && diff.changes == 0
    end

    def formatted_diffstat(width = 5)
      DiffHelper.format_diffstat_line(diff, width)
    end

    def octicon
      name =
        if diff.status_label == "moved"
          "renamed"
        elsif diff.status_label == "changed"
          "modified"
        else
          diff.status_label
        end
      "diff-#{name}"
    end

    def prepare_for_rendering!
      determine_hidden_diff_reason

      diff.text = nil if generated? || suppress_deletion?
    end

    def determine_hidden_diff_reason
      @hidden_diff_reason = case
      when suppress_deletion?
        :deleted
      when diff.too_big?
        :too_big
      when diff.text.blank?
        nil
      when generated?
        :generated
      end
    end

    def generated?
      !show_generated? && diff_blob.generated?
    end

    def suppress_deletion?
      !show_deleted? && diff.deleted?
    end

    def prose_diff?
      return @prose_diff if defined?(@prose_diff)
      @prose_diff = (
        probably_markup_renderable? &&
        GitHub::Markup.can_render?(path, diff_blob.data) &&
        diff.valid?
      )
    end

    # Heuristic to let us quickly return false for files that are probably not
    # markup renderable, since checking the type of all files with linguist is
    # relatively expensive.  If this returns true we should still check the
    # type using `GitHub::Markup.can_render?`
    def probably_markup_renderable?
      (
        !File.basename(path).include?(".") || # if the file has no extension, defer to linguist
        self.class.markup_path_pattern.match?(path)
      )
    end

    # A single regex that matches the extension of any file renderable by the github-markup gem.
    def self.markup_path_pattern
      @markup_path_pattern ||= begin
        # For each markup_impl, gather the extensions that Linguist knows about for all related languages.
        extensions = GitHub::Markup.markup_impls.map { |impl| impl.languages.map(&:extensions) }.flatten.uniq
        filenames = GitHub::Markup.markup_impls.map { |impl| impl.languages.map(&:filenames) }.flatten.uniq
        regexes = extensions.map { |ext| Regexp.new(Regexp.escape(ext), Regexp::IGNORECASE) }
        regexes.concat(filenames.map { |filename| %r[(?:\A|/)#{Regexp.escape(filename)}] }) # left-anchor on start of string or path separator
        /#{Regexp.union(regexes)}\z/
      end
    end

    def render_diff?
      return @render_diff if defined?(@render_diff)

      @render_diff = !!diff_blob.render_file_type_for_display(:diff)
    end

    def dependency_review_diff?
      return @dependency_review_diff if defined?(@dependency_review_diff)
      @dependency_review_diff = \
        logged_in? &&
        repository&.try(:dependency_graph_enabled?) &&
        repository&.try(:dependency_review_enabled?) &&
        DependencyManifestFile.recognized_path?(path: path) &&
        # Dependency review diffs do not support diffs that don't have a base sha
        diff.a_sha.present?
    end

    def toggleable?
      return @toggleable if defined?(@toggleable)
      @toggleable = code_rendering_service.rich_view_toggleable? ||
        !!diff_blob.render_file_type_for_display(:diff) || prose_diff? || dependency_review_diff?
    end

    def submodule_file_view
      return @submodule_file_view if defined?(@submodule_file_view)

      @submodule_file_view = Diff::SubmoduleFileView.new(
        repository: repository,
        diff_entry: diff,
      )
    end

    def binary_diff_size
      if diff.modified?
        diff_head_blob_size - diff_base_blob_size
      else
        diff_base_blob_size
      end
    end

    def binary_diff_percentage
      @binary_diff_percentage ||= if diff.added? || diff_base_blob_size == 0
        100
      elsif diff.deleted?
        -100
      else
        (diff_head_blob_size.to_f / diff_base_blob_size.to_f) * 100
      end
    end

    def display_diff_size?
      diff.binary? && (blob_a_size.present? || blob_b_size.present?)
    end

    def display_diff_size_percentage?
      !diff.added? && !diff.deleted? && !diff.renamed? && !diff.copied?
    end

    def blob_line_count
      diff_blob.try(:line_count) || 0
    end

    def has_expandable_hunks?
      # Get hunks that are not the top hunk header, where we show
      # a ... to note that it's the top of the diff.
      diff.enumerator.any? do |i|
        (
          i.type == :hunk &&
          !(
            i.current == 0 &&
            i.left == 0 &&
            i.nonewline == false &&
            i.position == 0 &&
            i.right == 0
          )
        )
      end
    end

    def show_expand_full_blob?(file_list_view)
      (
        file_list_view.expandable? &&
        has_expandable_hunks? &&
        blob_line_count > 0 &&
        !diff.added? &&
        !simple_rename? &&
        !diff.text.blank? &&
        !diff.binary? &&
        !hidden_diff_reason
      )
    end

    # Certain file types that were diffable via the render service are not diffabled via viewescreen
    # Additionally, some file types, like markdown, should always be diffable.
    # This method helps us to determine if a file type is considered diffable based on the environment
    # the app is running in and the type of file the user is looking at.
    # For a usage example, see the _diff_entry partial, where this method is used to
    # show or hide the `View the rich diff` button within the UI
    def supports_rich_diff?
      return true if prose_diff? || dependency_review_diff?
      return false if diff.deleted?
      code_rendering_service.supports_view?
    end

    def show_github_models_prompt_review?
      return false unless diff.path.end_with?(".prompt.yml", ".prompt.yaml")

      # Only allow reviewing prompts when the content changed
      return false if diff.added? || diff.deleted? || simple_rename?

      return false unless GitHubModels::Repository.new(repository: repository).models_enabled_for_repo?

      true
    end
  end
end
