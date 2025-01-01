# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Usage
      include Copilot::Signatures::Shared

      extend T::Helpers

      abstract!

      sig { override.returns(T::Boolean) }
      def can_export_premium_usage?
        # TODO: To be implemented.
        # This configuration will indicate to the UI whether the user can download the usage report
        # for Copilot Premium requests.
        false
      end

      sig { override.returns(T.nilable(String)) }
      def premium_usage_csv
        # TODO: to be implemented.
        # We will generate a CSV report that includes the following columns:
        #
        # Date - the date the usage was recorded
        # User - the user who generated the usage
        # Premium requests used - the number of premium requests used by the user
        # Monthly quota - the number of premium requests the user is allowed to use in a month
        nil
      end
    end
  end
end
