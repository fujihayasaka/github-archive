# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Usage
      include Copilot::Signatures::Shared
      include Copilot::Businesses::Signatures

      extend T::Helpers

      abstract!

      sig { override.returns(T::Boolean) }
      def can_export_premium_usage?
        # We enable the premium usage export as long as the enterprise has at least one paid seat.
        # Worst case scenario, the usage report will be empty if they are not using any premium requests.
        copilot_seat_count > 0
      end

      sig do
        override.params(
          user_id: Integer,
          start_date: T.nilable(T.any(Date, DateTime)),
          end_date: T.nilable(T.any(Date, DateTime))
        ).returns(T::Boolean)
      end
      def premium_usage_csv(user_id:, start_date: nil, end_date: nil)
        CopilotLimiter::Twirp.interactions_client.generate_csv(
          entity_id: business_object.id,
          entity_type: "Business",
          user_id: user_id,
          start_date: start_date,
          end_date: end_date,
        )
      end
    end
  end
end
