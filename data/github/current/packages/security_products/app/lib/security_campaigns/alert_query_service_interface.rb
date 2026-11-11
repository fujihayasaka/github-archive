# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AlertQueryServiceInterface
    extend T::Helpers
    interface!

    sig { abstract.params(include_alert_state: T::Boolean).returns([T::Array[T.untyped], T::Boolean, T.untyped]) }
    def counts_by_repo(include_alert_state: true); end
  end
end
