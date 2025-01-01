# typed: false
# frozen_string_literal: true

module Pages
  class JekyllConfigComponent < ApplicationComponent
    include SvgHelper
    include EscapeHelper

    attr_reader :repository
    attr_reader :params
    attr_reader :show_tip
    attr_reader :is_maintainer

    delegate :unsupported_pages, :is_user_pages_repo?, :has_gh_pages_branch?, :has_master_branch?, :has_gh_pages?, :pages_branch, :archived?, to: :repository

    def initialize(repository:, is_maintainer:, show_tip: nil)
      @repository = repository
      @show_tip = show_tip
      @is_maintainer = is_maintainer
    end

    memoize def has_gh_pages?
      @repository.has_gh_pages?
    end

    memoize def pages_branch_names
      @branches = @repository.heads.refs_with_default_first.map do |branch|
        {
          heading: scrubbed_utf8(branch.name),
          value: scrubbed_utf8(branch.name),
          selected: false
        }
      end
      if source && !@branches.find { |b| b[:value] == scrubbed_utf8(source) }
        @branches += [
          {
            heading: scrubbed_utf8(source),
            value: scrubbed_utf8(source),
            selected: false
          }
        ]
      end
      @branches += [
        {
          heading: "None",
          value: nil,
          selected: false
        }
      ]
      selected = @branches.find { |b| b[:value] == scrubbed_utf8(source) }

      # Set current selected branch.
      # If current source did not find in branch list, set last item (pages did not exist) to selected.

      selected ? selected[:selected] = true : @branches.last[:selected] = true
      @branches
    end

    def selected_branch_text
      selected = pages_branch_names.find { |s| s[:selected] }
      selected[:heading] if selected
    end

    def subdir_source?
      page && page.subdir_source?
    end

    def safe_pages_branch
      scrubbed_utf8(pages_branch)
    end

    def dir_button_text
      # Either return the selected folder's heading
      selected = select_dir.find { |s| s[:selected] }
      return selected[:heading] if selected && selected[:heading]

      # Or default to the first one (/) - this should never be called because in select_dir, when
      # there is no page, we fallback on the root option (when making a selection)
      select_dir[0][:heading]
    end

    def select_dir
      [
        {
          heading: "/ (root)",
          value: "/",
          selected: source_dir == "/" || !page
        },
        {
          heading: "/docs",
          value: "/docs",
          selected: source_dir == "/docs"
        }
      ]
    end

    def source
      page && page.source_branch
    end

    def source_dir
      page && page.source_dir
    end

    def button_text
      return "None" if !page
      source
    end

    def unpublish_documentation_url
      if is_user_pages_repo?
        "#{GitHub.help_url}/github/working-with-github-pages/unpublishing-a-github-pages-site#unpublishing-a-user-or-organization-site"
      elsif !is_user_pages_repo? && has_gh_pages_branch?
        "#{GitHub.help_url}/github/working-with-github-pages/unpublishing-a-github-pages-site#unpublishing-a-project-site"
      end
    end

    # Test for a .nojekyll page
    # If this is true, the Jekyll theme chooser becomes unavailable.
    def nojekyll?
      page.present? && page.nojekyll?
    end

    # Current or first available source from branch_list to auto-enable Pages
    # Defaults to default branch
    def default_source
      select_source = pages_branch_names.find { |s| s[:selected] && s[:value] != nil }
      return select_source if select_source
      return { heading: @repository.default_branch, value: @repository.default_branch } if is_user_pages_repo?
      { heading: "gh-pages", value: "gh-pages" }
    end

    private

    def scrubbed_utf8(text)
      return if text.nil?
      return text if text.encoding == ::Encoding::UTF_8 && text.valid_encoding?
      text.dup.force_encoding("UTF-8").scrub!
    end

    def page
      # Handle a preloaded `@repository.page` the same as a nil page
      # before it's persisted to the database
      return nil unless @repository.page && @repository.page.persisted?
      @repository.page
    end
  end
end
