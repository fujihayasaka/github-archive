# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Actions
  class TmpKV

    sig { params(partition_key: Integer).returns(GitHub::Config::DualWriteKV) }
    def self.for_partition_key(partition_key)
      config = GitHub::KV.config.dup
      config.table_name = :actions_key_values
      config.shard_key_column = :partition_key

      # Create a new KV instance for Actions
      local_kv = GitHub::KV.new(
        config: config,
        shard_key_value: partition_key
      ) do
        ApplicationRecord::Domain::RepositoriesActionsChecks.connection
      end

      # For now construct the dual write kv interface. Once the data is fully migrated
      # this can be changed to simply set @kv = local_kv
      flags = GitHub::Config::DualWriteKV::Flags.new(
        dual_read: :actions_checks_dual_read,
        dual_write: :actions_checks_dual_write,
        write_to_target: :actions_checks_write_to_target,
      )

      GitHub::Config::DualWriteKV.new(
        owner: "github/actions",
        kv_source: GitHub.kv, # rubocop:todo GitHub/DoNotUseGlobalKv
        kv_target: local_kv,
        flags: flags,
        shard_key_column: :partition_key,
        shard_key_value: partition_key
      )
    end

    sig { params(key: String).returns(GitHub::Config::DualWriteKV) }
    def self.for_key(key)
      config = GitHub::KV.config.dup
      config.table_name = :actions_key_values
      config.shard_key_column = :partition_key
      partition_key = Zlib::crc32(key)

      # Create a new KV instance for Actions
      local_kv = GitHub::KV.new(
        config: config,
        shard_key_value: partition_key
      ) do
        ApplicationRecord::Domain::RepositoriesActionsChecks.connection
      end

      # For now construct the dual write kv interface. Once the data is fully migrated
      # this can be changed to simply set @kv = local_kv
      flags = GitHub::Config::DualWriteKV::Flags.new(
        dual_read: :actions_checks_dual_read,
        dual_write: :actions_checks_dual_write,
        write_to_target: :actions_checks_write_to_target,
      )

      GitHub::Config::DualWriteKV.new(
        owner: "github/actions",
        kv_source: GitHub.kv, # rubocop:todo GitHub/DoNotUseGlobalKv
        kv_target: local_kv,
        flags: flags,
        shard_key_column: :partition_key,
        shard_key_value: partition_key
      )
    end
  end
end
