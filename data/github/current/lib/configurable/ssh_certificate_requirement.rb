# typed: true
# frozen_string_literal: true

# Whether org/business members are required to authenticate using SSH
# certificates for CLI Git access.
module Configurable
  module SshCertificateRequirement
    extend T::Helpers
    include Kernel
    requires_ancestor { Configurable }

    KEY = "ssh_certificate_requirement".freeze

    def enable_ssh_certificate_requirement(actor)
      return unless T.unsafe(self).config.enable!(KEY, actor)

      GitHub.instrument(
        "ssh_certificate_requirement.enable",
        ssh_certificate_requirement_instrumentation_payload(actor),
      )
    end

    def disable_ssh_certificate_requirement(actor)
      return unless T.unsafe(self).config.delete(KEY, actor)

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

      ssh_enabled && T.unsafe(self).config.enabled?(KEY) && usable_ssh_certificate_authorities.any?
    end

    def ssh_certificate_requirement_inherited?
      T.unsafe(self).config.inherited?(KEY)
    end

    # Is the feature enabled at a higher level?
    #
    # Returns boolean.
    def ssh_certificate_requirement_policy?
      ssh_certificate_requirement_enabled? && T.unsafe(self).config.inherited?(KEY)
    end

    def usable_ssh_certificate_authorities
      # Return cached value if it has already been computed or explicitly set.
      return @usable_ssh_certificate_authorities if defined?(@usable_ssh_certificate_authorities)

      @usable_ssh_certificate_authorities =
        usable_ssh_certificate_authorities_with_preload
    end

    def usable_ssh_certificate_authorities_with_preload
      if (defined?(Organization) && is_a?(Organization)) || (defined?(Business) && is_a?(Business))
        if T.unsafe(self).association(:ssh_certificate_authorities).loaded?
          if defined?(Business) && is_a?(Business)
            return ssh_certificate_authorities.to_a
          elsif defined?(Organization) && is_a?(Organization)
            if T.unsafe(self).association(:business).loaded?
              business_obj = business
              if business_obj.nil? || business_obj.association(:ssh_certificate_authorities).loaded?
                return (ssh_certificate_authorities + (business_obj&.ssh_certificate_authorities || [])).uniq
              end
            end
          end
        end
      elsif self.class.name == "Repository" && T.unsafe(self).association(:owner).loaded? && T.unsafe(self).owner.respond_to?(:usable_ssh_certificate_authorities)
        return T.unsafe(self).owner.usable_ssh_certificate_authorities
      end

      SshCertificateAuthority.usable_for(self).all
    end

    attr_writer :usable_ssh_certificate_authorities

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
