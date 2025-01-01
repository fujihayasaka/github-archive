# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module FeatureEnabled
      extend T::Helpers
      extend T::Sig
      include Copilot::Organizations::Signatures

      abstract!

      sig { params(feature_name: Symbol).returns(T::Boolean) }
      def feature_enabled?(feature_name)
        return true if organization_object.feature_enabled?(feature_name)

        return true if self.copilot_business&.business_object&.feature_enabled?(feature_name)

        false
      end
    end
  end
end
