# typed: true
# frozen_string_literal: true

# Whether org/business members are required to authenticate using SSH
# certificates for CLI Git access.
module Configurable
  module SshCertificateRequirement
    extend T::Helpers
    requires_ancestor { Configurable }

    KEY = "ssh_certificate_requirement".freeze

    def enable_ssh_certificate_requirement(actor)
      return unless config.enable!(KEY, actor)

      GitHub.instrument(
        "ssh_certificate_requirement.enable",
        ssh_certificate_requirement_instrumentation_payload(actor),
      )
    end

    def disable_ssh_certificate_requirement(actor)
      return unless config.delete(KEY, actor)

      GitHub.instrument(
        "ssh_certificate_requirement.disable",
        ssh_certificate_requirement_instrumentation_payload(actor),
      )
    end

    def ssh_certificate_requirement_enabled?
      ssh_enabled = if T.unsafe(self).respond_to?(:ssh_enabled?)
        T.unsafe(self).ssh_enabled?
      else
        GitHub.ssh_enabled?
      end

      ssh_enabled && config.enabled?(KEY) && usable_ssh_certificate_authorities.any?
    end

    def ssh_certificate_requirement_inherited?
      config.inherited?(KEY)
    end

    # Is the feature enabled at a higher level?
    #
    # Returns boolean.
    def ssh_certificate_requirement_policy?
      ssh_certificate_requirement_enabled? && config.inherited?(KEY)
    end

    def usable_ssh_certificate_authorities
      @usable_ssh_certificate_authorities ||= SshCertificateAuthority.usable_for(self).all
    end

    private

    def ssh_certificate_requirement_instrumentation_payload(actor)
      payload = { user: actor }

      case self
      when ::Organization
        payload[:org] = self
        payload[:business] = self.business if self.business
      when ::Business
        payload[:business] = self
      end

      payload
    end
  end
end
