# typed: strict
# frozen_string_literal: true

module Growth
  module CopilotOrganization
    extend T::Helpers

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

    sig { params(user: T.nilable(::User)).returns(T::Boolean) }
    def org_can_set_swe_agent_policy?(user)
      return false unless GitHub.copilot_enabled?
      return false unless user
      return false unless copilot_enabled?
      return false unless organization_object.adminable_by?(user)

      business = organization_object.business
      if business
        return false if business.trial?
        copilot_business = Copilot::Business.new(business)
        copilot_business.swe_agent_no_policy?
      else
        true
      end
    end

    sig { params(user: T.nilable(::User)).returns(T::Boolean) }
    def enterprise_can_set_swe_agent_policy?(user)
      return false unless GitHub.copilot_enabled?
      return false unless user
      return false unless copilot_enabled?

      business = organization_object.business
      return false unless business
      return false if business.trial?
      copilot_business = Copilot::Business.new(business)
      organization_object.delegate_billing_to_business? && (business.owner?(user))
    end

    sig { params(user: T.nilable(::User)).returns(T::Boolean) }
    def can_request_swe_agent_feature_from_enterprise?(user)
      return false unless GitHub.copilot_enabled?
      return false unless user
      return false unless copilot_enabled?
      return false unless organization_object.delegate_billing_to_business?
      return false unless organization_object.adminable_by?(user)
      return false unless business = organization_object.business
      return false if business.owner?(user)

      copilot_business = Copilot::Business.new(business)
      return false if copilot_business.swe_agent_no_policy? || copilot_business.swe_agent_enabled?

      true
    end
  end
end
