# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Mailable
      extend T::Helpers
      include Copilot::Organizations::Signatures

      abstract!

      sig { override.returns(T::Boolean) }
      def copilot_communication_opt_out?
        # if the organization itself has opted out, we can get out of here cheaply
        return true if organization_object.feature_enabled?(:copilot_communication_opt_out)

        # if the organization has no linked business, we can get out of here cheaply
        return false unless copilot_business

        # if the organization is linked to a business, we need to check the business
        T.must(copilot_business).copilot_communication_opt_out?
      end
    end
  end
end
