# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class EmailAgentMentionFilter < InputFilter
    def call(string)
      html = GitHub::Goomba::AgentMentionFilter.to_html(string, context, result)
      doc = Nokogiri::HTML.fragment(html)

      doc.traverse do |node|
        next unless node.element?
        next unless node.name == "gh:agent-mention"

        replacement = build_replacement_for(node)
        node.replace(replacement)
      end

      replace_copilot_mentions!(doc)

      doc.to_html
    end

    private

    def build_replacement_for(node)
      token = node["token"].to_s
      original = node["original"].presence || node.content.presence || ""

      build_agent_link(token, original)
    end

    def build_agent_link(token, original)
      normalized = normalized_token(token)
      return original if normalized.blank?

      agent = find_agent_for_token(normalized)
      return original unless agent

      repository = repository_context
      return original unless repository && agent.enabled_for_repository?(repository, current_user)

      doc_url = agent.doc_url
      return original unless doc_url.present?

      display_text = original.presence || "@#{normalized}[agent]"

      helpers.link_to(display_text, doc_url, class: "user-mention")
    rescue => error
      GitHub.dogstats.increment("goomba.email_agent_mention_filter.failure", tags: ["error:#{error.class.name}"])
      original
    end

    def normalized_token(token)
      token&.downcase
    end

    def find_agent_for_token(token)
      ::AgenticApp.all_agents.find do |agent|
        normalized_token(agent.display_name) == token
      end
    end

    def repository_context
      entity = context[:entity]
      entity.is_a?(::Repository) ? entity : nil
    end

    def current_user
      context[:current_user]
    end

    def helpers
      @helpers ||= EmptyController.new.view_context
    end

    def replace_copilot_mentions!(doc)
      doc.traverse do |node|
        next unless node.text?

        text = node.text
        next unless text.include?("@copilot")

        replaced = GitHub::HTML::MentionFilter.mentioned_logins_in(text) do |match, login, is_info|
          if login.casecmp("copilot").zero? && !is_info
            match.sub("@#{login}", build_agent_link("copilot", "@copilot"))
          else
            match
          end
        end

        next if replaced == text

        node.replace(Nokogiri::HTML.fragment(replaced))
      end
    end
  end
end
