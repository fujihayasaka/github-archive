# typed: true
# frozen_string_literal: true
module Gists
  # Controls the gist snippet view
  # eg https://github.com/gists/defunkt
  #
  # Created via Gists::SnippetView.new(:gist => gist, :blob => blob)
  #
  # Blob can be nil
  class SnippetView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::TextHelper
    include BasicHelper, TextHelper
    include ForkCountingMethods

    attr_reader :gist

    delegate :owner, :user_param, :recently_created?, :visibility, :anonymous?, to: :gist

    # How many files do we have?
    def file_count_info
      pluralize gist.files.count, "file"
    end

    # How many forks do we have?
    def fork_count_info
      pluralize fork_count, "fork"
    end

    # How many comments do we have?
    def comment_count_info
      pluralize gist.comment_count, "comment"
    end

    # How many stars do we have?
    def star_count_info
      # current_user - The viewer, will be nil/false for anonymous users.
      # true - Indicates that we want to filter for spammy here.
      pluralize gist.stargazer_count(current_user, true), "star"
    end

    # Generate an HTML formatted gist description.
    #
    # Returns the HTML description.
    def formatted_description
      @formatted_description ||= formatted_gist_description(gist)
    end

    def date_info_text
      recently_created? ? "Created" : "Last active"
    end

    def date_info_date
      recently_created? ? gist.created_at : gist.updated_at
    end

    def blob
      @blob ||= truncate_blob(gist.files.first)
    end

    def can_show_snippet?
      blob.present? && !gist.access.disabled?
    end

    private

    # Truncate the blob to be usable as a snippet
    #
    # blob - A Gist blob to grab the first 1024 bytes of content/maximum of 11 lines.
    #
    # Returns the modified blob (data reset to the truncated data)
    def truncate_blob(blob)
      return unless blob.present?

      first_kb = blob.data[0, 1024]
      lines = first_kb.split("\n", Gist::MAX_SNIPPET_LINES)[0, (Gist::MAX_SNIPPET_LINES - 1)]

      # For markdown files, we need to parse the final line to avoid truncating in
      # the middle of a HTML element (e.g. `<img sr`) unless we are within a code block
      # or the final line is a blockquote
      lines[-1] = truncate_html(lines[-1], lines[-1].length) if blob.markdown? && first_kb.count("`") % 2 == 0 && !lines[-1].starts_with?("> ")

      snippet = lines.join("\n")
      blob.data = snippet
      blob.snippet = true
      blob
    end
  end
end
