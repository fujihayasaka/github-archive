# typed: true
# frozen_string_literal: true

module Configurable
  module AuditLogCodeSearchEvents
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "audit_log_code_search_events_enabled".freeze

    class NonBusinessError < StandardError; end

    def enable_audit_log_code_search_events(actor: nil)
      audit_log_code_search_events_ensure_business!
      return unless config.enable!(KEY, actor)

      instrument_audit_log_code_search_events(actor, "enable")
    end

    def audit_log_code_search_events_enabled?
      return false if GitHub.enterprise?
      return false unless self.is_a?(Business)
      return false unless self.feature_flag_enabled?(:code_search_query_processor, default: false)

      config.get(KEY).present?
    end

    def disable_audit_log_code_search_events(actor: nil)
      audit_log_code_search_events_ensure_business!
      config.delete(KEY, actor) unless config.get(KEY).nil?
      instrument_audit_log_code_search_events(actor, "disable")
    end

    private

    def audit_log_code_search_events_ensure_business!
      unless self.is_a?(Business)
        raise NonBusinessError.new \
          "Only Businesses are eligible for this feature."
      end
    end

    def instrument_audit_log_code_search_events(actor, state)
      title = "business"
      payload = { actor: actor, business: self }

      GitHub.instrument("#{title}.#{state}_audit_log_code_search_events", payload)

      GitHub.dogstats.increment(
        "toggle_audit_log_code_search_events", tags: ["state:#{state}d", "type:#{title}"],
      )
    end
  end
end
