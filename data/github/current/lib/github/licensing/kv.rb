# typed: strict
# frozen_string_literal: true

module Licensing
  class KV

    OWNER = "github/licensing"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = :licensing_key_values

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Billing.connection }
    end
  end
end
