# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module AlertQueryServiceInterface
    extend T::Helpers
    interface!

    sig { abstract.returns([T::Array[T.untyped], T::Boolean, T.untyped]) }
    def counts_by_repo; end
  end
end
