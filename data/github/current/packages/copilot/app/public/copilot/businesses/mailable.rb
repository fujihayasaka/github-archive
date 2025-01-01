# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Mailable
      extend T::Helpers
      include Copilot::Businesses::Signatures

      abstract!

      sig { override.returns(T::Boolean) }
      def copilot_communication_opt_out?
        # we are allowing entire businesses to opt out.
        # this will help with Microsoft especially.
        business_object.feature_enabled?(:copilot_communication_opt_out)
      end
    end
  end
end
