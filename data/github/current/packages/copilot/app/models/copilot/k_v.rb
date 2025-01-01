# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "k_v/data_store"

module Copilot
  class KV
    OWNER = "github/copilot"

    @kv = T.let(nil, T.nilable(GitHub::Config::DualWriteKV))

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Copilot::KV::DataStore.table_name
      local_kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Copilot.connection }

      # for now construct the dual write kv interface. this can be removed once all
      # writes and reads have been turned on (once write_to_target is enabled)
      flags = GitHub::Config::DualWriteKV::Flags.new(
        dual_read: :copilot_job_dual_read,
        dual_write: :copilot_job_dual_write,
        write_to_target: :copilot_job_write_to_target
      )

      # rubocop:todo GitHub/DoNotUseGlobalKv this is temporary for dual-write and will be removed
      @kv = GitHub::Config::DualWriteKV.new(owner: OWNER, kv_source: GitHub.kv, kv_target: local_kv, flags: flags)
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end
  end
end
