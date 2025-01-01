# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  module IConcurrencyLimiter
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.params(sku: Codespaces::Skus::Sku, location: String, blk: T.proc.returns(T::untyped)).void }
    def reserve_capacity(sku:, location:, &blk); end

    sig { abstract.returns(Integer) }
    def enforce_concurrency_limits!; end
  end
end
