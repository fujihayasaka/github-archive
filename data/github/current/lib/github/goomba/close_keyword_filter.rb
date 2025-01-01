# typed: false
# frozen_string_literal: true

module GitHub::Goomba
  class CloseKeywordFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper
    SELECTOR = Goomba::Selector.new(match: ":text", reject: "pre :text, code :text, a :text")
    ISSUE_CLOSING_LOCATIONS = %w[Commit PullRequest].freeze

    # Note: The following are copied with capture names added from GitHub::HTML::IssueMentionFilter.
    #   We should try to migrate them from here to the goomba mention filter when that pipeline is retired.

    # Example: "Fixes: "
    # Note: no \z in order to allow matches like "Fixes #45"
    # Note: Expect one or more spaces at the end to avoid false matches like owner/fixops#1
    CLOSE_TEXT = /\b(?<close_text>close[sd]?|fix(e[sd])?|resolve[sd]?)(?<close_spacer>\s*:?\s+)/i.freeze

    CLOSE_WITH_TEXT_REFERENCE = /#{CLOSE_TEXT}#{GitHub::Goomba::IssueMentionFilter::ISSUE_REFERENCE}/.freeze
    CLOSE_AT_END_OF_TEXT = /#{CLOSE_TEXT}\z/.freeze

    def self.cache_key(context)
      [
        context[:location],
        # from @issue_mention_filter.call
        GitHub::Goomba::IssueMentionFilter.cache_key(context),
      ].reject(&:blank?).join(":")
    end

    def self.enabled?(context)
      location_permits_close_keyword_highlighting?(context[:location])
    end

    def initialize(*args)
      super
      @issue_mention_filter = GitHub::Goomba::IssueMentionFilter.new(context, GitHub::HTML::Result.new, {})
    end

    def selector
      SELECTOR
    end

    # Public: Returns a human-readable description of the location the Markdown appears, based on
    # the given location string.
    def self.location_description(location)
      if location == "Commit"
        "commit"
      elsif %w[PullRequest PullRequestComment].include?(location)
        "pull request"
      elsif location == "IssueComment"
        "issue"
      end
    end

    # Public: Returns a highlighted keyword that triggers closing an issue or marking an issue/PR
    # as a duplicate.
    #
    # number - the number of the target issue or pull request
    # location - a string from the pipeline context for where this bit of Markdown appeared
    # close_text - optional; a string keyword for closing an issue; required if `duplicate_text` is
    #              nil
    # duplicate_text - optional; a string keyword for marking this issue or PR as a duplicate;
    #                  required if `close_text` is nil
    # target - a string summarizing whether the thing being mentioned was an issue or pull request
    #
    # Returns a string of HTML.
    def self.highlight_keyword(number:, location:, close_text: nil, target: "issue")
      return unless keyword = close_text || duplicate_text

      tooltip = "This #{location} closes #{target} ##{number}."

      attrs = {
        class: "issue-keyword tooltipped tooltipped-se",
        "aria-label": tooltip,
      }

      ActionController::Base.helpers.content_tag(:span, keyword, attrs)
    end

    def call(node)
      return unless self.class.location_permits_close_keyword_highlighting?(context[:location])

      html = node.to_html

      # match close keywords at beginning or embedded in the body of the text
      html.gsub!(CLOSE_WITH_TEXT_REFERENCE) do |_original|
        match = Regexp.last_match
        close_text = match[:close_text]
        number = match[:number]
        nwo = nil
        nwo = match[:name_or_nwo] if match.named_captures.keys.include?("name_or_nwo")

        closes_tag = ActionController::Base.helpers.content_tag("gh:closes", nil,
          text: close_text, nwo: nwo, number: number)

        safe_join([closes_tag, match[:full_reference]], match[:close_spacer])
      end

      # match close keywords at end of text preceding an issue link
      html.gsub!(CLOSE_AT_END_OF_TEXT) do |original|
        match = Regexp.last_match
        next original unless issue_mention_node = node.next_sibling
        next original unless issue_mention_node = issue_mentionize_node(issue_mention_node)

        close_text = match[:close_text]
        if issue_mention_node =~ GitHub::Goomba::Async::IssueMentionFilter::ISSUE_ATTR_SELECTOR
          data = JSON.parse(issue_mention_node["gh:issue-mention"])
          nwo, number = data["nwo"], data["number"]
        else
          nwo = issue_mention_node["nwo"]
          number = issue_mention_node["number"]
        end

        closes_tag = ActionController::Base.helpers.content_tag("gh:closes", nil,
          text: close_text, nwo: nwo, number: number)

        safe_join([closes_tag, match[:close_spacer]])
      end

      html
    end

    # Internal: If a user enters text like "Closes #1" in certain places, such as in a commit
    # message or in the body of a pull request, then that text results in an issue being closed.
    # However, if such text is in a comment on an issue or a comment in a pull request (an
    # IssueComment), nothing happens and we should not highlight it.
    #
    # TODO make this a private instance method once HTML::CloseKeywordFilter is removed from service
    #
    # Returns a Boolean.
    def self.location_permits_close_keyword_highlighting?(location)
      ISSUE_CLOSING_LOCATIONS.include?(location)
    end

    # Internal: Given a string of text and another string to find within it, this will return an
    # array with two strings: the text before and the text after that target string.
    #
    # all_text - a string containing `target_text`; the "haystack" to look through
    # target_text - a substring of `all_text`; the "needle" to look for
    #
    # TODO make this a private instance method once HTML::CloseKeywordFilter is removed from service
    #
    # Returns an array with two strings.
    def self.surrounding_text(all_text:, target_text:)
      start_index = all_text.index(/\b(#{target_text})\b/i)
      end_index = start_index + target_text.length

      before_text = all_text[0...start_index]
      after_text = all_text[end_index...all_text.length]

      [before_text, after_text]
    end

    private

    def issue_mentionize_node(node)
      return nil unless is_element_node?(node)
      return node if node.matches(GitHub::Goomba::Async::IssueMentionFilter::SELECTOR)

      if node.matches(GitHub::Goomba::IssueMentionFilter.selector)
        fragment_text = @issue_mention_filter.call(node)
        if fragment_text.nil? && node["gh:issue-mention"]
          # If IssueMentionFilter modified the node in place, take the node HTML
          # as our fragment text and restore the actual node in document to the
          # way it was.
          fragment_text = node.to_html
          node.remove_attribute("gh:issue-mention")
        end
        return nil unless fragment_text

        fragment = Goomba::DocumentFragment.new(fragment_text)
        return nil if fragment.children.count != 1

        gh_node = fragment.children.first
        return gh_node if gh_node.matches(GitHub::Goomba::Async::IssueMentionFilter::SELECTOR)
      end
    end
  end
end
