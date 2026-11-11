# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Converts markdown-style merge queue links to HTML anchor tags in email notifications.
  #
  # This filter transforms:
  #   [merge queue](https://github.com/owner/repo/queue/branch)
  # Into:
  #   <a href="https://github.com/owner/repo/queue/branch">merge queue</a>
  #
  class EmailMergeQueueLinkFilter < InputFilter
    # Regex to match markdown links with "merge queue" text
    # Matches: [merge queue](url)
    MERGE_QUEUE_LINK_PATTERN = /\[merge queue\]\(([^)]+)\)/i

    def call(string)
      string.gsub(MERGE_QUEUE_LINK_PATTERN) do |_match|
        url = $1
        escaped_url = ERB::Util.html_escape(url)
        "<a href=\"#{escaped_url}\">merge queue</a>"
      end
    end
  end
end
