# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class AgentMentionFilter < TextFilter
    IGNORE_PARENTS = GitHub::HTML::AgentMentionFilter::IGNORE_PARENTS.map { |parent| "#{parent} :text" }.join(", ")
    SELECTOR = Goomba::Selector.new(match: ":text", reject: IGNORE_PARENTS)

    def self.feature_flags
      [:agentshq_mention]
    end

    def self.enabled?(context)
      mentions_enabled?(context) && is_pull_request?(context)
    end

    def self.cache_key(context)
      "agentshq_mention" if mentions_enabled?(context)
    end

    def self.mentions_enabled?(context)
      feature_flag_enabled?(:agentshq_mention, context)
    end

    def self.is_pull_request?(context)
      context[:subject_type] == "PullRequest" ||
        context[:location] == "PullRequest" ||
        context[:location] == "PullRequestComment" ||
        context[:subject].is_a?(PullRequestReview) ||
        context[:subject].is_a?(PullRequestReviewComment)
    end

    def self.feature_flag_enabled?(flag, context)
      actor = repository_from_context(context)
      if actor
        FeatureFlag.vexi.enabled?(flag, actor, default: false)
      else
        FeatureFlag.vexi.enabled?(flag, default: false)
      end
    end

    def initialize(*args)
      super
      @mentions_enabled = self.class.mentions_enabled?(context)
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

    private

    def mentions_enabled?
      @mentions_enabled
    end
  end
end
