# typed: true
# frozen_string_literal: true

module Configurable
  module AuditLogSourceIpDisclosure
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Object }

    KEY = "source_ip_disclosure_enabled".freeze

    # Raised when attempting to enable for a non-emu business.
    class NonBusinessOrOrganizationError < StandardError; end

    def enable_source_ip_disclosure(actor: nil)
      unless self.is_a?(Business) || self.is_a?(Organization)
        raise NonBusinessOrOrganizationError.new \
          "Only Businesses and Organizations are eligible for this feature."
      end

      return unless config.enable!(KEY, actor)
      instrument_source_ip_disclosure_events(actor, "enable")
    end

    def source_ip_disclosure_enabled?
      config.get(KEY).present?
    end

    def disable_source_ip_disclosure(actor: nil)
      config.delete(KEY, actor) unless config.get(KEY).nil?
      instrument_source_ip_disclosure_events(actor, "disable")
    end

    private

    def instrument_source_ip_disclosure_events(actor, state)
      title = ""
      payload = {}
      if self.is_a?(Organization)
        title = "org"
        payload = { user: actor, org: self }
      elsif self.is_a?(Business)
        title = "business"
        payload = { user: actor, business: self }
      end

      GitHub.instrument("#{title}.#{state}_source_ip_disclosure", payload)

      GitHub.dogstats.increment(
        "toggle_source_ip_disclosure", tags: ["state:#{state}d", "type:#{title}"]
      )

      instrument_source_ip_disclosure_hydro_message(actor, state)
    end

    def instrument_source_ip_disclosure_hydro_message(actor, state)
      if self.is_a?(Organization)
        GlobalInstrumenter.instrument("organization.toggle_source_ip_disclosure", {
          organization: self.is_a?(Organization) ? self : nil,
          actor: actor,
          state: state == "enable" ? :ENABLED : :DISABLED
          })
      elsif self.is_a?(Business)
        GlobalInstrumenter.instrument("enterprise_account.toggle_source_ip_disclosure", {
          enterprise: self.is_a?(Business) ? self : nil,
          actor: actor,
          state: state == "enable" ? :ENABLED : :DISABLED
        })
      end
    end
  end
end
