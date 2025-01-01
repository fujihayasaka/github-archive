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
      # settings. This method checks all the possible ways an Organizaiton might
      # be on an Copilot Enterprise plan and if the org is on CE, they can edit
      # CE settings.
      #
      # Note: there are other methods that sound like they would do this but
      # they usually encapsulate just one aspect of checking for Copilot
      # Enterprise. For example there is
      # Copilot::Organization#copilot_plan_enterprise but this doesn't return
      # trials.
      #
      # If you want to cover all the possible ways an organization might be on
      # an Copilot Enterprise plan to check if someone can use Copilot Enterprise features, use this method.
      sig { returns(T::Boolean) }
      def can_use_copilot_enterprise_features?
        return true if copilot_business&.feature_enabled?(:copilot_mixed_licenses) && self.copilot_plan_enterprise?

        !!copilot_business&.copilot_plan_enterprise? ||
          (!!business_trial&.copilot_plan_enterprise? && business_trial&.active?) ||
          !!copilot_business&.business_object&.feature_enabled?(:copilot_for_enterprise)
      end
    end
  end
end
