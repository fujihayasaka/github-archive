# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Copilot
      class BuyBoxComponent < ApplicationComponent
        extend T::Sig
        include ApplicationComponent::Rescuable

        rescue_from ActiveRecord::ActiveRecordError, with: :nothing

        sig { returns(T.nilable(::Organization)) }
        attr_reader :organization

        sig { params(organization: T.nilable(::Organization)).void }
        def initialize(organization:)
          @organization = organization
        end

        sig { returns(T::Boolean) }
        def render?
          GitHub.billing_enabled? && organization.present?
        end

        sig { returns(MemberFeatureRequest::Feature::CopilotForBusiness) }
        def copilot_for_business_feature
          MemberFeatureRequest::Feature::CopilotForBusiness
        end

        sig { returns(T.nilable(Integer)) }
        memoize def total
          MemberFeatureRequest.total_for_feature(T.must(organization), copilot_for_business_feature)
        end

        sig { returns(String) }
        def copilot_signup_path
          copilot_business_signup_organization_payment_path(org: organization)
        end
      end
    end
  end
end
