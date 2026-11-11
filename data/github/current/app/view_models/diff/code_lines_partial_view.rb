# typed: true
# frozen_string_literal: true

module Diff
  # Controls the display of lines in a diff entry.
  class CodeLinesPartialView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include DiffHelper
    include UrlHelper

    # The repository these diff lines are from.
    attr_reader :repository

    # An GitHub::Diff::Entry.
    attr_reader :diff_entry

    # If false, commenting on these lines will be disabled.
    attr_reader :commentable

    # A GitHub::Diff::RelatedLinesEnumerator for the lines to display.
    attr_reader :line_enumerator

    # Blob properties.
    attr_reader :blob, :path

    # The anchor for the file or diff discussion.
    attr_reader :anchor

    # If false, no bottom expander will be displayed for these lines.
    attr_reader :bottom_expander

    # If false, will disable expansion from any hunk headers.
    attr_reader :expandable

    # A ReviewThreads collection.
    attr_reader :threads

    # A DiffAnnotations collection.
    attr_reader :annotations

    # Determining if the repository is a wiki or not.¬
    attr_reader :in_wiki_context

    # Render the comment thread on each diff line if true.
    attr_reader :show_comments

    # The PullRequest, if any, the diff is being viewed in the context of.
    attr_reader :pull_request

    def after_initialize
      @line_enumerator ||= diff_entry.enumerator
      @blob ||= diff_blob(self.diff_entry)
      @path ||= self.diff_entry.path
      @anchor ||= diff_path_anchor(self.path)
    end

    def blob_sha
      self.blob.try(:sha)
    end

    def mode
      self.blob.try(:mode)
    end

    # implement current_repository so that our helpers work.
    def current_repository
      self.repository
    end

    def expandable?
      self.expandable && self.blob_line_count > 0
    end

    def bottom_expander?
      self.expandable && self.bottom_expander && !self.blob.nil?
    end

    def blob_line_count
      self.blob.try(:line_count) || 0
    end

    def highlighting_mode
      if in_wiki_context || found_highlighted_lines_in_cache?
        Diffs::DeferredDiffLinesComponent::HighlightingModes::IMMEDIATE
      else
        Diffs::DeferredDiffLinesComponent::HighlightingModes::DEFERRED
      end
    end

    # Syntax-highlights and highlights intra-line changes in a line from a
    # diff.
    #
    # line - A GitHub::Diff::Line.
    #
    # Returns an HTML String.
    def highlighted_line(line)
      HighlightedDiffLine.for_line(line, html_lines: syntax_highlighted_lines).to_html
    end

    private

    def found_highlighted_lines_in_cache?
      if @syntax_highlighted_lines_cache_code.nil?
        syntax_highlighted_lines
      end

      @syntax_highlighted_lines_cache_code != :miss
    end

    def syntax_highlighted_lines
      return @syntax_highlighted_lines if defined?(@syntax_highlighted_lines)
      return @syntax_highlighted_lines = nil unless diff_entry

      cache_code, lines = SyntaxHighlightedDiff.new(repository).frozen_colorized_lines_with_cache_code(diff_entry)

      @syntax_highlighted_lines_cache_code = cache_code
      @syntax_highlighted_lines = lines
    end
  end
end
