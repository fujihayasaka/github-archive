# typed: true
# frozen_string_literal: true

module Configurable
  module AuditLogApiRequestEvents
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Object }

    REQUEST_EVENTS_KEY = "api_request_events_enabled".freeze

    # Raised when attempting to enable for a non-emu business.
    class NonBusinessError < StandardError; end

    def enable_api_request_events(actor: nil)
      ensure_business!
      return unless config.enable!(REQUEST_EVENTS_KEY, actor)

      instrument_api_request_events(actor, "enable")
    end

    def api_request_events_enabled?
      return false unless self.is_a?(Business)
      return false unless GitHub.flipper[:audit_log_api_events_write].enabled?(self)

      config.get(REQUEST_EVENTS_KEY).present?
    end

    def disable_api_request_events(actor: nil)
      ensure_business!
      return unless self.is_a?(Business)
      config.delete(REQUEST_EVENTS_KEY, actor) unless config.get(REQUEST_EVENTS_KEY).nil?
      instrument_api_request_events(actor, "disable")
    end

    private

    def ensure_business!
      unless self.is_a?(Business)
        raise NonBusinessError.new \
          "Only Businesses are eligible for this feature."
      end
    end

    def instrument_api_request_events(actor, state)
      title = "business"
      payload = { actor: actor, business: self }

      GitHub.instrument("#{title}.#{state}_api_request_events", payload)

      GitHub.dogstats.increment(
        "toggle_api_request_events", tags: ["state:#{state}d", "type:#{title}"]
      )
    end

  end
end
