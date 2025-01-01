# typed: strict
# frozen_string_literal: true

module Billing
  class Kv
    extend T::Sig

    sig { void }
    def self.initialize
      @kv = T.let(nil, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      # this will be the remaining implementation once the migration is complete
      cfg = GitHub::KV.config.dup
      cfg.table_name = :billing_key_values
      @kv = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Billing.connection }
      @kv
    end
  end
end
