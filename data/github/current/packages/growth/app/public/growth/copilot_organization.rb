# typed: strict
# frozen_string_literal: true

module Growth
  module CopilotOrganization
    extend T::Helpers
    extend T::Sig
    include Copilot::Organizations::Signatures

    abstract!

    sig { params(user: T.nilable(::User)).returns(T::Boolean) }
    def can_enable_org_to_assign_seats?(user)
      return false unless GitHub.copilot_enabled?
      return false unless user
      return false if copilot_enabled?
      return false unless business = organization_object.business
      return false if business.trial?

      organization_object.delegate_billing_to_business? && business.owner?(user)
    end

    sig { params(user: T.nilable(::User)).returns(T::Boolean) }
    def can_request_copilot_from_enterprise?(user)
      return false unless GitHub.copilot_enabled?
      return false unless user
      return false if copilot_enabled?
      return false unless organization_object.delegate_billing_to_business?
      return false unless organization_object.adminable_by?(user)
      return false unless business = organization_object.business
      return false if business.owner?(user)

      true
    end
  end
end
