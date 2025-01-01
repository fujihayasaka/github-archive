# typed: true
# frozen_string_literal: true

# This configurable is for EMU proxy security header customers
module Configurable
  module ProxySecurityHeader
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "proxy_security_header".freeze
    ENABLE_INSTRUMENTATION_KEY = "business.proxy_security_header_enabled"
    DISABLE_INSTRUMENTATION_KEY = "business.proxy_security_header_disabled"

    UNSUPPORTED_ENTERPRISE_ERROR = "Enterprise does not support configuring proxy security header."
    ENTERPRISE_ACTOR_REQUIRED_ERROR = "Proxy security header can only be configured by a GitHub employee."
    CORRECT_ACTOR_REQUIRED_ERROR = "Proxy security header can only be configured by the enterprise admin or a GitHub employee."

    # Raise when proxy security header has issues when configuring.
    class ProxySecurityHeaderError < StandardError; end

    # Public: Enable proxy security header on the object.
    #
    # actor - The User enabling the setting, must be the business owner or GitHub employee.
    def enable_proxy_security_header(actor: nil)
      unless eligible_for_proxy_security_header?
        raise ProxySecurityHeaderError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      if FeatureFlag.vexi.enabled?(:enterprise_access_verification_ga, business, default: false)
        unless business&.owner?(actor) || actor&.employee?
          raise ProxySecurityHeaderError.new CORRECT_ACTOR_REQUIRED_ERROR
        end
      else
        unless actor&.employee?
          raise ProxySecurityHeaderError.new ENTERPRISE_ACTOR_REQUIRED_ERROR
        end
      end

      return unless config.enable(KEY, actor)

      instrument_proxy_security_header(name: ENABLE_INSTRUMENTATION_KEY, actor: actor)
    end

    # Public: Disable proxy security header on the object.
    #
    # actor - The User disabling the setting, must be the business owner or GitHub employee.
    def disable_proxy_security_header(actor: nil)
      unless eligible_for_proxy_security_header?
        raise ProxySecurityHeaderError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      if FeatureFlag.vexi.enabled?(:enterprise_access_verification_ga, business, default: false)
        unless business&.owner?(actor) || actor&.employee?
          raise ProxySecurityHeaderError.new CORRECT_ACTOR_REQUIRED_ERROR
        end
      else
        unless actor&.employee?
          raise ProxySecurityHeaderError.new ENTERPRISE_ACTOR_REQUIRED_ERROR
        end
      end

      return unless config.delete(KEY, actor)

      instrument_proxy_security_header(name: DISABLE_INSTRUMENTATION_KEY, actor: actor)
    end

    # Public: Is the proxy security header enabled on the object?
    #
    # Returns Boolean.
    def proxy_security_header_enabled?
      config.enabled?(KEY)
    end

    # Public: Is the object eligible for proxy security header configuration?
    #  An enterprise must be an EMU business.
    #
    # Returns Boolean.
    def eligible_for_proxy_security_header?
      return false if GitHub.multi_tenant_enterprise?
      return false if GitHub.enterprise?
      return false unless self.is_a?(Business)
      return false unless self.enterprise_managed_user_enabled?

      true
    end

    private

    # Private: Instrument the event for enabling/disabling proxy security header.
    # Params:
    # name - The String name of the event.
    # actor - The User enabling/disabling the setting.
    #
    # Returns nothing.
    def instrument_proxy_security_header(name:, actor:)
      payload = {
        actor: actor,
        business: self,
      }

      GitHub.instrument(name, payload)
    end

    def business
      self.is_a?(Business) ? self : nil
    end
  end
end
