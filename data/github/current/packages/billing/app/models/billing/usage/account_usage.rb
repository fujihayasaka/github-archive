# typed: strict
# frozen_string_literal: true

module Billing::Usage
  class AccountUsage
    include GitHub::Memoizer

    sig { returns(ActiveSupport::HashWithIndifferentAccess) }
    attr_reader :raw_account_usage

    sig { params(raw_account_usage: T::Hash[Symbol, T.untyped]).void }
    def initialize(raw_account_usage)
      @raw_account_usage = T.let(
        raw_account_usage.with_indifferent_access,
        ActiveSupport::HashWithIndifferentAccess
      )
    end

    sig { returns(T::Array[Billing::Usage::ProductUsage]) }
    memoize def product_usages
      raw_account_usage[:product_usage].map do |usage|
        Billing::Usage::ProductUsage.new(usage)
      end
    end

    sig { returns(Numeric) }
    memoize def account_id
      raw_account_usage[:account][:account_id]
    end
  end
end
