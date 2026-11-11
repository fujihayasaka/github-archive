# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Removes model selection suffixes (e.g., "+claude-opus-4.5") from coding agent mentions
  # for display purposes. The model information is preserved in the raw comment body.
  #
  # Supports both @copilot mentions (rendered as <gh:user-mention>) and third-party
  # agent mentions like @claude[agent] or @codex[agent] (rendered as <gh:agent-mention>).
  class CopilotModelMentionFilter < TextFilter
    IGNORE_PARENTS = %w[pre code a tt].map { |tag| "#{tag} :text" }.join(", ")
    SELECTOR = Goomba::Selector.new(match: ":text", reject: IGNORE_PARENTS)
    MODEL_SUFFIX_PATTERN = /\A\+[a-zA-Z0-9._-]+/

    def self.feature_flags
      [:coding_agent_model_selection, :coding_agent_third_party_model_ui]
    end

    def self.enabled?(context)
      feature_flag_enabled?(:coding_agent_model_selection, context)
    end

    def self.cache_key(context)
      if enabled?(context)
        third_party = feature_flag_enabled?(:coding_agent_third_party_model_ui, context) ? "_3p" : ""
        "copilot_model_mention#{third_party}"
      end
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
      @third_party_model_ui_enabled = self.class.feature_flag_enabled?(:coding_agent_third_party_model_ui, context)
    end

    def selector
      SELECTOR
    end

    def call(text)
      html = text.html

      return nil unless html.start_with?("+")
      return nil unless previous_sibling_is_agent_mention?(text)

      replaced = html.sub(MODEL_SUFFIX_PATTERN, "")
      replaced if replaced != html
    end

    private

    def previous_sibling_is_agent_mention?(text)
      prev = text.previous_sibling
      return false unless prev

      if prev.respond_to?(:to_html)
        prev_html = prev.to_html
        if prev_html.start_with?("<gh:user-mention")
          return prev["login"]&.downcase == "copilot"
        elsif @third_party_model_ui_enabled && prev_html.start_with?("<gh:agent-mention")
          return true
        elsif prev.respond_to?(:name) && prev.name == :a
          return false unless prev["class"]&.include?("user-mention")
          link_text = prev.text_content&.strip&.downcase
          return link_text == "@copilot"
        end
      end

      false
    end
  end
end
