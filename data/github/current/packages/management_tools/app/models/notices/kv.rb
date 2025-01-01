# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Notices
  class Kv
    OWNER = "github/feature_management"

    @kv = T.let(nil, T.nilable(GitHub::Config::DualWriteKV))

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.store
      return @kv if @kv

      # this is a temporary exemption until the data is migrated to the new table
      kv_source = GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv

      # this will be the remaining implementation once the migration is complete
      cfg = GitHub::KV.config.dup
      cfg.table_name = Notices::Kv::DataStore.table_name

      kv_target = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::FeatureManagement.connection }

      flags = GitHub::Config::DualWriteKV::Flags.with_prefix(:notices)

      @kv = GitHub::Config::DualWriteKV.new(owner: OWNER, kv_source:, kv_target:, flags:)
      @kv
    end
  end
end
