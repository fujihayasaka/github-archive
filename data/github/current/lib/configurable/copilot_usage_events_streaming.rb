# typed: true
# frozen_string_literal: true

module Configurable
  module CopilotUsageEventsStreaming
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "copilot_usage_events_streaming_enabled".freeze

    class NonBusinessError < StandardError; end

    def enable_copilot_usage_events_streaming(actor: nil)
      copilot_usage_events_streaming_ensure_business!
      return unless config.enable!(KEY, actor)

      instrument_copilot_usage_events_streaming(actor, "enable")
    end

    def copilot_usage_events_streaming_enabled?
      return false unless self.is_a?(Business)

      config.get(KEY).present?
    rescue Configs::RpcError
      false
    end

    def disable_copilot_usage_events_streaming(actor: nil)
      copilot_usage_events_streaming_ensure_business!
      return unless self.is_a?(Business)
      return if config.get(KEY).nil?

      config.delete(KEY, actor)
      instrument_copilot_usage_events_streaming(actor, "disable")
    end

    private

    def copilot_usage_events_streaming_ensure_business!
      unless self.is_a?(Business)
        raise NonBusinessError.new \
          "Only Businesses are eligible for this feature."
      end
    end

    def instrument_copilot_usage_events_streaming(actor, state)
      title = "business"
      payload = { actor: actor, business: self }

      GitHub.instrument("#{title}.#{state}_copilot_usage_events_streaming", payload)

      GitHub.dogstats.increment(
        "toggle_copilot_usage_events_streaming", tags: ["state:#{state}d", "type:#{title}"]
      )
    end
  end
end
