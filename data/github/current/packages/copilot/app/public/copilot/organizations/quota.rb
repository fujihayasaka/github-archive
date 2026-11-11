# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Quota
      include GitHub::Memoizer
      include Copilot::Organizations::Signatures

      extend T::Helpers

      abstract!

      sig { returns(T.nilable(T::Boolean)) }
      def eligible_for_direct_org_billing?
        return unless direct_org_billing_enabled?
        validate_org_event_eligibility[:is_eligible]
      end

      sig { returns(T.nilable(String)) }
      def org_event_eligibility_denial_reason
        return unless direct_org_billing_enabled?
        validate_org_event_eligibility[:denial_reason]
      end

      private

      sig { returns({ is_eligible: T::Boolean, denial_reason: T.nilable(String) }) }
      memoize def validate_org_event_eligibility
        CopilotLimiter::Twirp.quota_client.validate_org_event_eligibility(copilot_tracking_id: organization_object.analytics_tracking_id)
      end

      sig { returns(T::Boolean) }
      memoize def direct_org_billing_enabled?
        organization_object.feature_flag_enabled?(:copilot_code_review_direct_org_billing, default: false) ||
          !!organization_object.business&.feature_flag_enabled?(:copilot_code_review_direct_org_billing, default: false)
      end
    end
  end
end
