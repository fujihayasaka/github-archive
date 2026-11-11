# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class AgentMentionFilter < TextFilter
    IGNORE_PARENTS = GitHub::HTML::AgentMentionFilter::IGNORE_PARENTS.map { |parent| "#{parent} :text" }.join(", ")
    SELECTOR = Goomba::Selector.new(match: ":text", reject: IGNORE_PARENTS)

    def self.enabled?(context)
      is_pull_request?(context)
    end

    def self.cache_key(_context)
      "agentshq_mention"
    end

    def self.is_pull_request?(context)
      context[:subject_type] == "PullRequest" ||
        context[:location] == "PullRequest" ||
        context[:location] == "PullRequestComment" ||
        context[:subject].is_a?(PullRequestReview) ||
        context[:subject].is_a?(PullRequestReviewComment)
    end

    def selector
      SELECTOR
    end

    def call(text)
      html = text.html
      return nil unless GitHub::HTML::AgentMentionFilter.likely_agent_mention?(html)

      replaced = GitHub::HTML::AgentMentionFilter.mentioned_agents_in(html) do |match, token, mention|
        node = ActionController::Base.helpers.content_tag("gh:agent-mention", nil, token: token, original: mention)
        match.sub(mention, node)
      end

      replaced if replaced != text.html
    end
  end
end
