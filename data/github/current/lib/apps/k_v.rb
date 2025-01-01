# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "k_v/data_store"

module Apps
  class KV
    extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig
    OWNER = "github/apps"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Apps::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::IntegrationsLodge.connection }
    end
  end
end
