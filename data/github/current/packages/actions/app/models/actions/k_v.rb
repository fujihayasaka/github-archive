# typed: true
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Actions
  class KV

    sig { params(partition_key: Integer).returns(GitHub::KV) }
    def self.for_partition_key(partition_key)
      config = GitHub::KV.config.dup
      config.table_name = :actions_key_values
      config.shard_key_column = :partition_key

      GitHub::KV.new(config: config, shard_key_value: partition_key) do
        ApplicationRecord::Domain::RepositoriesActionsChecks.connection
      end
    end

    sig { params(key: String).returns(GitHub::KV) }
    def self.for_key(key)
      config = GitHub::KV.config.dup
      config.table_name = :actions_key_values
      config.shard_key_column = :partition_key
      partition_key = Zlib::crc32(key)

      # Create a new KV instance for Actions
      GitHub::KV.new(config: config, shard_key_value: partition_key) do
        ApplicationRecord::Domain::RepositoriesActionsChecks.connection
      end
    end
  end
end
