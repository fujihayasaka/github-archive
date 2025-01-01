# typed: strict
# frozen_string_literal: true

module Orca
  class RateLimit

    sig { params(organization: Organization).void }
    def initialize(organization)
      @rate_limit = T.let(Orca.client.get_rate_limit(organization: organization), T.nilable(GitHub::Orca::RateLimitDetails))
    end

    sig { returns(T.nilable(String)) }
    def reset_at
      value = @rate_limit&.reset_at
      return nil if value.nil? || value.zero?

      Time.at(value).utc.iso8601.to_s
    end

    sig { returns(T::Boolean) }
    def within_rate_limit?
      return true if @rate_limit.nil?

      @rate_limit.is_rate_limited == false
    end

    sig { returns(T.nilable(T.any(Symbol, Integer))) }
    def reason
      return nil if @rate_limit.nil?
      @rate_limit.reason
    end
  end
end
