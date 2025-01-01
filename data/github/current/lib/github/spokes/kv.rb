# typed: strict
# frozen_string_literal: true

require "github/spokes/kv/data_store"

module Spokes
  class KV
    OWNER = "github/spokes"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Spokes::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Spokes.connection }
    end
  end
end
