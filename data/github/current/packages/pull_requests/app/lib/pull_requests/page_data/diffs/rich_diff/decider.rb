# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::RichDiff

  # This class encapsulates all the logic used for determining
  # if we are working with a rich diff and if we should default to displaying the rich diff
  # It works together in tandem with the Renderer class
  class Decider
    sig { returns(T::Boolean) }
    attr_reader :default_to_rich_diff

    sig { returns(T::Boolean) }
    attr_reader :is_rich_diff

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        diff_entry_blob: T.nilable(TreeEntry),
        code_rendering_service: CodeRenderingService::DiffComponent,
        short_path: T.nilable(String),
        skip_dependency_review: T::Boolean,
      ).void
    end
    def initialize(diff_entry:, diff_entry_blob:, code_rendering_service:, short_path:, skip_dependency_review:)
      @diff_entry = diff_entry
      @diff_entry_blob = diff_entry_blob
      @code_rendering_service = code_rendering_service
      @short_path = short_path
      @skip_dependency_review = skip_dependency_review

      @default_to_rich_diff = T.let(false, T::Boolean)
      @is_rich_diff = T.let(false, T::Boolean)

      calculate_rich_diff
    end

    # A single regex that matches the extension of any file renderable by the github-markup gem.
    sig { returns(Regexp) }
    def self.markup_path_pattern
      @markup_path_pattern ||= T.let(
        begin
              # For each markup_impl, gather the extensions that Linguist knows about for all related languages.
              extensions = GitHub::Markup.markup_impls.map { |impl| impl.languages.map(&:extensions) }.flatten.uniq
              filenames = GitHub::Markup.markup_impls.map { |impl| impl.languages.map(&:filenames) }.flatten.uniq
              regexes = extensions.map { |ext| Regexp.new(Regexp.escape(ext), Regexp::IGNORECASE) }
              regexes.concat(filenames.map { |filename| %r[(?:\A|/)#{Regexp.escape(filename)}] }) # left-anchor on start of string or path separator
              /#{Regexp.union(regexes)}\z/
            end,
        T.nilable(Regexp),
      )
    end

    # Heuristic to let us quickly return false for files that are probably not
    # markup renderable, since checking the type of all files with linguist is
    # relatively expensive.  If this returns true we should still check the
    # type using `GitHub::Markup.can_render?`
    sig { returns(T::Boolean) }
    def probably_markup_renderable?
      (
        !File.basename(@diff_entry.path).include?(".") || # if the file has no extension, defer to linguist
        self.class.markup_path_pattern.match?(@diff_entry.path)
      )
    end

    sig { returns(T::Boolean) }
    def is_prose_diff?
      blob_data = safe_get_blob_data

      probably_markup_renderable? &&
        GitHub::Markup.can_render?(@diff_entry.path, blob_data) &&
        @diff_entry.valid?
    end

    sig { returns(T::Boolean) }
    def toggleable?
      @can_toggle_rich_diff ||= T.let(begin
        return false if @diff_entry.binary?

        @code_rendering_service.rich_view_toggleable? ||
          safe_render_file_type_for_display ||
          is_prose_diff? ||
          dependency_review_diff?
      end, T.nilable(T::Boolean))
    end

    sig { returns(T::Boolean) }
    def supports_rich_diff?
      return true if is_prose_diff? || dependency_review_diff?
      return false if @diff_entry.deleted?

      @code_rendering_service.supports_view? || false
    end

    sig { returns(T::Boolean) }
    def dependency_review_diff?
      # Dependency review diffs do not support diffs that don't have a base sha
      DependencyManifestFile.recognized_path?(path: @diff_entry.path) && @diff_entry.a_sha.present?
    end

    private

    sig { void }
    def calculate_rich_diff
      file_type = File.extname(@diff_entry.path)
      diff_short_path_value = File.basename(@diff_entry.path)
      match_path = @short_path && diff_short_path_value && @short_path == diff_short_path_value

      skip_dependency_review_for_file = @skip_dependency_review && dependency_review_diff?

      if @diff_entry.deleted? || (@diff_entry.modified? && @diff_entry.b_blob.nil?)
        # File mode changed, without a content change or deleted
        can_display_rich_diff = false
        should_default_to_rich_diff = false
      elsif @code_rendering_service.supports_view?
        can_display_rich_diff = @diff_entry.similarity != 100 # 100 means the file content is identical so we don't need to show a rich diff
        should_default_to_rich_diff = @code_rendering_service.default_to_rich_diff_view?
      else # legacy render check and prose diff (Markdown type views)
        can_display_rich_diff = true
        should_default_to_rich_diff = (@diff_entry.binary? || file_type == ".svg") && supports_rich_diff?
      end

      should_display_rich_diff = (
        !skip_dependency_review_for_file && match_path || should_default_to_rich_diff
      )

      @default_to_rich_diff = (can_display_rich_diff && should_display_rich_diff) || false
      # Binary images can have rich diff even without toggles, other files need toggleable support
      @is_rich_diff = (!skip_dependency_review_for_file && can_display_rich_diff && (@diff_entry.binary? || toggleable?)) || false
    end

    # Safely call render_file_type_for_display without modifying frozen objects (ie - tests)
    sig { returns(T::Boolean) }
    def safe_render_file_type_for_display
      return false unless @diff_entry_blob

      diff_entry_blob = @diff_entry_blob.frozen? ? @diff_entry_blob.dup : @diff_entry_blob
      !!diff_entry_blob.render_file_type_for_display(:diff)
    end

    # Safely get blob data without modifying frozen objects (ie - tests)
    sig { returns(String) }
    def safe_get_blob_data
      return "" unless @diff_entry_blob

      diff_entry_blob = @diff_entry_blob.frozen? ? @diff_entry_blob.dup : @diff_entry_blob
      diff_entry_blob.data || ""
    end
  end
end
