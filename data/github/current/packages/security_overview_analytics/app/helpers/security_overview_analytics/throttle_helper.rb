# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class ThrottleHelper
    extend T::Helpers
    extend T::Sig

    abstract!
    sealed!

    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def self.throttle_kv_writes_with_fallback(&blk)
      ApplicationRecord::Domain::KeyValues.throttle_writes(&blk)
    rescue => err # rubocop:disable Lint/GenericRescue
      ActiveRecord::Base.connected_to(role: :writing) do
        blk.call
      end
    end
  end
end
