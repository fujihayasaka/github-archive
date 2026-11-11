# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class AgentMentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers
    SELECTOR = Goomba::Selector.new(match: "gh|agent-mention")

    def self.feature_flags
      GitHub::Goomba::AgentMentionFilter.feature_flags
    end

    def self.enabled?(context)
      GitHub::Goomba::AgentMentionFilter.enabled?(context)
    end

    def self.cache_key(context)
      GitHub::Goomba::AgentMentionFilter.cache_key(context)
    end

    def initialize(*args)
      super
      @agent_cache = {}
    end

    def selector
      SELECTOR
    end

    def async_scan
      tokens_by_normalized = {}

      @nodes.each do |node|
        raw_token = node["token"]
        next if raw_token.blank?

        normalized = normalized_token(raw_token)
        next unless normalized

        tokens_by_normalized[normalized] ||= raw_token
      end

      Promise.all(tokens_by_normalized.map do |normalized_token, _raw_token|
        next unless context[:entity].is_a?(::Repository)

        agent = find_agent_for_token(normalized_token)
        next unless agent
        next unless agent.integration

        # Only include agents that are mentionable
        next unless agent.mentionable?

        # Only include agents that are enabled for this repository
        next unless agent.enabled_for_repository?(context[:entity], current_user)

        agent.integration.async_bot.then do |bot|
          next unless bot
          @agent_cache[normalized_token] = {
            agent: agent,
            bot: bot
          }
        end
      end)
    end

    def call(node)
      token = node["token"]
      fallback = node["original"] || node.to_html

      normalized = normalized_token(token)
      return fallback if normalized.nil?

      cached_entry = @agent_cache[normalized]
      return fallback if cached_entry.nil?

      agent = cached_entry[:agent]
      bot = cached_entry[:bot]

      doc_url = agent.doc_url
      display_text = build_display_text(node)

      helpers.profile_link(bot, class: "user-mention notranslate", url: doc_url) { display_text }
    end

    private

    def build_display_text(node)
      token = node["token"].to_s
      return node["original"] if token.blank?

      normalized = normalized_token(token)
      return node["original"] if normalized.nil?

      "@#{normalized}[agent]"
    end

    def normalized_token(token)
      return unless token
      token.to_s.downcase
    end

    # We define a `profile_link` on all rails controllers, so instantiating one is the easiest way to call that method.
    def helpers
      return @view_context if defined?(@view_context)
      @view_context = EmptyController.new.view_context
    end

    def find_agent_for_token(token)
      ::AgenticApp.all_agents.find do |agent|
        normalized_token(agent.display_name) == token
      end
    end
  end
end
