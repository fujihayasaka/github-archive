# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Growth
  module LastActivity
    class KV
      sig { returns(GitHub::KV) }
      def self.store
        @store ||= T.let(build_store, T.nilable(GitHub::KV))
      end

      sig { returns(GitHub::KV) }
      def self.build_store
        config = GitHub::KV.config.dup
        config.table_name = :growth_last_activity_key_values

        flags = GitHub::Config::DualWriteKV::Flags.new(
          dual_read: :growth_last_activity_kv_dual_read,
          dual_write: :growth_last_activity_kv_dual_write,
          write_to_target: :growth_last_activity_kv_dual_write_to_target,
        )
        @store = GitHub::KV.new(config: config) { ApplicationRecord::Domain::UsersCollab.connection }
        @store
      end
    end
  end
end
