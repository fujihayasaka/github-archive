# typed: true
# frozen_string_literal: true

module Configurable
  module AutoApprovePersonalAccessTokenGrantRequests
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    KEY = "auto_approve_pat_grant_requests"

    ENABLE_INSTRUMENTATION_KEY  = "personal_access_token.auto_approve_grant_requests_enabled"
    DISABLE_INSTRUMENTATION_KEY = "personal_access_token.auto_approve_grant_requests_disabled"
    RESET_INSTRUMENTATION_KEY = "personal_access_token.auto_approve_grant_requests_reset"

    class AutoApprovalRestrictedError < StandardError; end
    class AutoApprovalEnforcedError < StandardError; end

    # Public: Disable PAT access requests from being auto approved.
    #
    # actor - The User enabling the setting.
    #
    # Returns nothing.
    #
    # Raises AutoApprovalRestrictedError if a a higher level object is explicitly
    # restricting enablement.
    def enable_auto_pat_request_approval(actor:)
      if pat_requests_auto_approval_restricted_policy?
        raise AutoApprovalRestrictedError, "Your organization is not permitted to enable auto approval."
      end

      return unless config.enable!(KEY, actor)
      instrument_enablement(actor)
    end

    # Public: Disable PAT access requests from being auto approved.
    #
    # actor - The User disabling the setting.
    #
    # Returns a nothing.
    #
    # Raises AutoApprovalEnforcedError if a a higher level object is explicitly
    # enforcing enablement.
    def disable_auto_pat_request_approval(actor:)
      if pat_requests_auto_approval_enforced_policy?
        raise AutoApprovalEnforcedError, "Your organization is not permitted to disable auto approval."
      end

      return unless config.disable!(KEY, actor)
      instrument_disablement(actor)
    end

    # Public: Reset grant request auto-approval setting.
    #
    # actor - The User disabling the setting.
    #
    # Returns a nothing.
    def reset_auto_pat_request_approval(actor:)
      return unless config.delete(KEY, actor)
      instrument_auto_approval_reset(actor)
    end

    def pat_requests_auto_approved?
      config.enabled?(KEY)
    end

    # Public: Is the business delegating the auto-approval of
    # grant requests to the current organization?
    #
    # Applies to businesses or their organizations.
    #
    # Returns a Boolean.
    def pat_requests_auto_approval_delegated_policy?
      return config.get(KEY).nil? if instance_of?(Business)
      return true if instance_of?(Organization) && !configuration_owner.instance_of?(Business)

      configuration_owner.config.get(KEY).nil?
    end

    # Public: Is the business enforcing the auto-approval of
    # grant requests for the current organization?
    #
    # Applies only to organizations owned by a business.
    #
    # Returns a Boolean.
    def pat_requests_auto_approval_enforced_policy?
      pat_requests_auto_approved? && config.inherited?(KEY)
    end

    # Public: Is the business restricting the auto-approval of
    # grant requests for the current organization?
    #
    # Applies only to organizations owned by a business.
    #
    # Returns a Boolean.
    def pat_requests_auto_approval_restricted_policy?
      config.get(KEY) == false && config.inherited?(KEY)
    end

    private

    def instrument_enablement(actor)
      payload = auto_approval_instrumentation_payload(actor)

      GitHub.instrument(ENABLE_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(ENABLE_INSTRUMENTATION_KEY, payload)
    end

    def instrument_disablement(actor)
      payload = auto_approval_instrumentation_payload(actor)

      GitHub.instrument(DISABLE_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(DISABLE_INSTRUMENTATION_KEY, payload)
    end

    def instrument_auto_approval_reset(actor)
      payload = auto_approval_instrumentation_payload(actor)

      GitHub.instrument(RESET_INSTRUMENTATION_KEY, payload)
      GlobalInstrumenter.instrument(RESET_INSTRUMENTATION_KEY, payload)
    end

    def auto_approval_instrumentation_payload(actor)
      {}.tap do |p|
        p[:user] = actor

        case self
        when Business
          p[:business] = self
        when Organization
          p[:org] = self
          p[:business] = self.business if self.business
        end
      end
    end
  end
end
