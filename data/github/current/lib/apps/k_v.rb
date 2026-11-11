# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "k_v/data_store"

module Apps
  class KV
    extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig
    OWNER = "github/apps"

    @kv = T.let(nil, T.nilable(GitHub::Config::DualWriteKV))

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.store
      return @kv if @kv

      source_config = GitHub::KV.config.dup
      source_config.table_name = LodgeDataStore.table_name
      kv_source = GitHub::KV.new(config: source_config) { ApplicationRecord::Domain::IntegrationsLodge.connection }

      target_config = GitHub::KV.config.dup
      target_config.table_name = AbilitiesDataStore.table_name
      kv_target = GitHub::KV.new(config: target_config) { ApplicationRecord::Domain::IamAbilities.connection }

      @kv = GitHub::Config::DualWriteKV.new(
        owner: OWNER,
        kv_source: kv_source,
        kv_target: kv_target,
        flags: GitHub::Config::DualWriteKV::Flags.with_prefix(:apps_kv),
      )
    end
  end
end
