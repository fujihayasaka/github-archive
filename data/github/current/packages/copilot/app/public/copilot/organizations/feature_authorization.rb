# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    # Whether an organization can change Copilot Enterprise settings like knowledge bases and custom instructions
    module FeatureAuthorization
      extend T::Helpers
      include Copilot::Organizations::Signatures
      include Copilot::Organizations::Settings

      abstract!

      # See: https://github.com/github/copilot-core-productivity/issues/1293
      # See: https://github.com/github/copilot-core-productivity/issues/1810
      #
      # An org must have a Copilot Enterprise plan to change Copilot Enterprise
      # settings. This method checks all the possible ways an Organization might
      # be on a Copilot Enterprise plan and if the org is on CE, they can edit
      # CE settings.
      #
      # Note: there are other methods that sound like they would do this but
      # they usually encapsulate just one aspect of checking for Copilot
      # Enterprise. For example there is
      # Copilot::Organization#copilot_plan_enterprise but this doesn't return
      # trials.
      #
      # If you want to cover all the possible ways an organization might be on
      # a Copilot Enterprise plan to check if someone can use Copilot Enterprise features, use this method.
      sig { returns(T::Boolean) }
      def can_use_copilot_enterprise_features?
        return true if self.copilot_plan_enterprise?

        !!copilot_business&.copilot_plan_enterprise? ||
          (!!business_trial&.copilot_plan_enterprise? && business_trial&.active?) ||
          !!copilot_business&.business_object&.feature_flag_enabled?(:copilot_for_enterprise, default: false)
      end

      sig { returns(T::Boolean) }
      def can_use_org_copilot_custom_instructions?
        # Org-wide custom instructions was opened up to Copilot Business
        # plans: https://github.com/github/copilot-productivity/issues/5366
        #
        # We also allow orgs with a trial since they are also on a Copilot Business/Enterprise plan while trialing.
        can_use_copilot_enterprise_features? || has_copilot_for_business? || !!(business_trial&.active?)
      end
    end
  end
end
