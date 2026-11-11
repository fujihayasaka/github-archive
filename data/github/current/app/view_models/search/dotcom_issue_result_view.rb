# typed: true
# frozen_string_literal: true

module Search
  class DotcomIssueResultView < IssueResultView

    attr_reader :created_at, :updated_at, :author, :issue_link, :pull_request, :private

    alias :pull_request? :pull_request
    alias :private? :private

    # Create a new IssueResultView from an `issue` document hash returned from
    # the dotcom api.
    #
    # hash - Document Hash returned by dotcom API
    #
    def initialize(dotcom_hash, viewer = nil)

      @id        = dotcom_hash["id"]
      @title     = dotcom_hash["title"]
      @body      = dotcom_hash["body"] || ""
      @state     = dotcom_hash["state"]
      @number    = dotcom_hash["number"]
      @author    = dotcom_hash["user"] || User.ghost
      @comments  = dotcom_hash["comments"]
      @repo      = dotcom_hash["repository"]
      @private   = @repo["private"]

      @created_at = Time.parse(dotcom_hash["created_at"])
      @updated_at = Time.parse(dotcom_hash["updated_at"])

      @issue_link   = dotcom_hash["html_url"]
      @pull_request = dotcom_hash["pull_request"]

      @highlights  = Search::DotcomHighlights.highlights(dotcom_hash["text_matches"])

      @viewer = viewer

      if pull_request && pull_request["merged_at"].present?
        @state = "merged"
      end
    end

    # Returns a highlighted text fragment to be displayed along with the other
    # pertinent issue information. The highlighted text will either be from
    # the issue body or from the issue comments (if the body contains no
    # highlighted terms).
    #
    # The returned string is already HTML escaped and html_safe.
    #
    # Returns an HTML escaped text String.
    def hl_text
      return @hl_text if defined? @hl_text

      @hl_text =
          if highlights? && @highlights.key?("body")
            @highlights["body"].first
          else
            ERB::Util.force_escape(@body)
          end

      if @hl_text.length > FRAGMENT_SIZE
        last = @hl_text[FRAGMENT_SIZE..-1].index(/\s/).to_i + FRAGMENT_SIZE
        @hl_text = @hl_text.slice(0, last) + " ..."
      end
      @hl_text.html_safe # rubocop:disable Rails/OutputSafety
    end
  end  # DotcomIssueResultView
end  # Search
