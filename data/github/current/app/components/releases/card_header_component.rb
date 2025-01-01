# typed: true
# frozen_string_literal: true

module Releases
  class CardHeaderComponent < ApplicationComponent
    renders_one :additional_buttons
    renders_one :additional_labels

    def initialize(release, repository, is_latest:, writable:, is_link: false, show_minimal: false, show_author_line: true, highlights: nil, with_h1: false)
      @release = release
      @current_repository = repository
      @is_latest = is_latest
      @writable = writable
      @is_link = is_link
      @show_minimal = show_minimal
      @show_author_line = show_author_line
      @highlights = highlights
      @with_h1 = with_h1
    end

    attr_reader :release, :current_repository, :show_minimal, :show_author_line, :highlights, :with_h1

    def is_latest?
      @is_latest
    end

    def writable?
      @writable
    end

    def maybe_link_title
      if @is_link
        render(Primer::Beta::Link.new(href: release_path(release), scheme: :primary)) { release_display_name }
      else
        release_display_name
      end
    end

    # use ActionView highlight helper to wrap the phrases to highlight in release name in <mark> tags
    # The highlighter defaults to <mark>\1</mark>. Set the <mark> class to "hx_keyword-hl" to improve the color contrast in dark theme.
    def release_display_name
      if @highlights&.any?
        highlights = @highlights&.uniq&.map { |h| html_escape(h.strip) }

        highlight(
          html_escape(release.display_name),
          highlights,
          highlighter: '<mark class="hx_keyword-hl">\1</mark>'
        )
      else
        release.display_name
      end
    end

    def commit_href
      if release.tagged?
        commit_path release.tag.commit, @current_repository
      end
    end

    def tag_href
      conflict = current_repository.refs.unqualified_name_conflict?(release.tag.name_for_display)
      tree_path "", conflict ? release.tag.qualified_name_for_display : release.tag.name_for_display
    end
  end
end
