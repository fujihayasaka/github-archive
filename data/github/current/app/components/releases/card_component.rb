# typed: true
# frozen_string_literal: true

module Releases
  class CardComponent < ApplicationComponent
    include CachedOcticonHelper
    include StacksHelper

    RELEASE_TRUNCATE_LENGTH = 750

    renders_one :additional_buttons

    def initialize(release, repository, is_latest:, is_link: false, show_minimal: false, show_author_line: !show_minimal, open_assets: true, writable: false, classes: "", show_stack: false, highlights: nil, truncate_assets: false, hpc: false, with_h1: false)
      @release = release
      @current_repository = repository
      @is_latest = is_latest
      @is_link = is_link
      @show_minimal = show_minimal
      @open_assets = open_assets
      @classes = classes
      @writable = writable
      @show_author_line = show_author_line
      @show_stack = show_stack
      @highlights = highlights
      @truncate_assets = truncate_assets
      @hpc = hpc
      @with_h1 = with_h1
    end

    attr_reader :release, :current_repository, :show_minimal, :open_assets, :is_latest, :is_link, :show_author_line, :show_stack, :highlights, :truncate_assets, :hpc, :with_h1

    def writable?
      @writable
    end

    def body_content
      if show_minimal
        short_description_html_info[:html]
      else
        @highlights&.key?("body") ? highlighted_body : @release.body_html
      end
    end

    def is_body_truncated?
      !!@release.is_body_truncated
    end

    def tag_info
      release.display_body
    end

    def show_stack_button?
      @show_stack && !@release.prerelease && show_stack_template_button?(@current_repository)
    end

    def show_footer?
      show_assets = release.tagged? || release.uploaded_assets.any?
      show_reactions = release.published?

      show_assets || show_reactions || show_mentions?
    end

    def show_mentions?
      release.mentions.any?
    end

    def short_description_html_truncated?
      short_description_html_info[:truncated?]
    end

    memoize def short_description_html_info
      @release.short_description_html_info(length: RELEASE_TRUNCATE_LENGTH)
    end

    def expandable?
      show_minimal && short_description_html_truncated?
    end

    def expand_url
      expanded_card_url(user_id: current_repository.owner_display_login, repository: current_repository.name, name: release.tag_name)
    end

    def classes
      expandable? ? @classes + " js-release-expandable" : @classes
    end

    # If ES returns results in the highlight hash, extract the token that is surrounded by the <mark> tags and pass to ActionView highlighting helper.
    # The highlighter defaults to <mark>\1</mark>. Set the <mark> class to "hx_keyword-hl" to improve the color contrast in dark theme.

    def highlighted_body
      highlight_phrases = @highlights&.fetch("body", nil) || []
      highlight_phrases = highlight_phrases.uniq.map { |string| string.slice(/<mark>(.*?)<\/mark>/, 1) }
      highlight(@release.body_html, highlight_phrases, highlighter: '<mark class="hx_keyword-hl">\1</mark>')
    end

    def hl_release_name
      @highlights&.fetch("name", nil) || []
    end
  end
end
