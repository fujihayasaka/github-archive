# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class CloseKeywordFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "gh|closes")

    def async_scan
      Promise.resolve(nil)
    end

    def self.cache_key(context)
      context[:location]
    end

    def self.enabled?(context)
      # this filter requires the rich issue mention filter to already be run, in order to find issue references
      # this filter should only be run when the rich issue mention filter is also enabled
      GitHub::Goomba::Async::RichIssueMentionFilter.enabled?(context)
    end

    def call(node)
      issue_reference = reference_from_node(node)
      return node["text"] unless issue_reference

      # we need to set the reference type to closes because we finally know this is a valid
      # issue closing reference.
      issue_reference.type = issue_reference.type.presence || node["text"]

      highlight_keyword(
        number: node["number"],
        location: context[:location],
        close_text: node["text"],
        target: issue_reference.pull_request? ? "pull request" : "issue",
      )
    end

    def selector
      SELECTOR
    end

    # Internal: Returns a human-readable description of the location the Markdown appears, based on
    # the given location string.
    # TODO make this a private instance method once HTML::CloseKeywordFilter is removed from service
    def self.location_description(location)
      if location == "Commit"
        "commit"
      elsif %w[PullRequest PullRequestComment].include?(location)
        "pull request"
      elsif location == "IssueComment"
        "issue"
      end
    end

    private

    def reference_from_node(node)
      return nil if scratch[:issue_references].blank?

      key = [node["nwo"], node["number"].to_i]
      scratch[:issue_references][key]
    end

    # Internal: Returns a highlighted keyword that triggers closing an issue or marking an issue/PR
    # as a duplicate.
    #
    # number - the number of the target issue or pull request
    # location - a string from the pipeline context for where this bit of Markdown appeared
    # close_text - optional; a string keyword for closing an issue; required if `duplicate_text` is
    #              nil
    # target - a string summarizing whether the thing being mentioned was an issue or pull request
    #
    # Returns a string of HTML.
    def highlight_keyword(number:, location:, close_text: nil, target: "issue")
      if self.context[:subject].is_a?(Issue) && self.context[:subject].pull_request?
        if !self.context[:subject].pull_request.close_issues_on_merge_permitted?
          return ActionController::Base.helpers.content_tag(:span, close_text, { class: "issue-keyword" })
        end
      end

      tooltip = "This #{self.class.location_description(location)} closes #{target} ##{number}."

      attrs = {
        class: "issue-keyword tooltipped tooltipped-se",
        "aria-label": tooltip,
      }

      ActionController::Base.helpers.content_tag(:span, close_text, attrs)
    end
  end
end
