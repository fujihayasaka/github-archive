# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require "github/assets/kv/data_store"

module Assets
  class KV
    OWNER = "github/lfs"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Assets::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::AssetKeyValues.connection }
    end
  end
end
