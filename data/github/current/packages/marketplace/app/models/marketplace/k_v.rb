# typed: strict
# frozen_string_literal: true

require_relative "k_v/data_store"

module Marketplace
  class KV
    OWNER = "github/marketplace"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Marketplace::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Integrations.connection }
    end
  end
end
