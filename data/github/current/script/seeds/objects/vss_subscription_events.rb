# typed: strict
# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    class VssSubscriptionEvent
      sig { params(payload: String, investigation_notes: T.nilable(String), status: T.nilable(String)).returns(::Licensing::Vss::VssSubscriptionEvent) }
      def self.create(payload:, investigation_notes: nil, status: "unprocessed")
        ::Licensing::Vss::VssSubscriptionEvent.create!(
          payload: payload,
          parsed_payload: JSON.parse(payload),
          investigation_notes: investigation_notes,
          status: status,
        )
      end
    end
  end
end
