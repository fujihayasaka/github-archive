# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Usage
      include Copilot::Signatures::Shared
      include Copilot::Users::Signatures

      extend T::Helpers

      abstract!

      sig { override.returns(T::Boolean) }
      def can_export_premium_usage?
        # We enable the premium usage export as long as the user is a paid Copilot user (Pro or Pro Plus)
        # or the user has complimentary access (education, OSS, coupons, etc.).
        # Worst case scenario, the usage report will be empty if they are not using any premium requests.
        has_cfi_access? && (has_paid_access? || has_trial_subscription? || has_free_access?)
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
          entity_id: user_object.id,
          entity_type: "User",
          user_id: user_id,
          start_date: start_date,
          end_date: end_date,
        )
      end
    end
  end
end
