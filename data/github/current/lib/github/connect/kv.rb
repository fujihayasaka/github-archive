# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require "github/connect/kv/data_store"

module Connect
  class KV
    OWNER = "github/connect"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Connect::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Users.connection }
    end
  end
end
