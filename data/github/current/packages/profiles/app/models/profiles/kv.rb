# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Profiles
  class Kv
    extend T::Sig
    OWNER = "github/profiles"

    @kv = T.let(nil, T.nilable(GitHub::Config::DualWriteKV))

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.store
      return @kv if @kv

      # this is a temporary exemption until the data is migrated to the new table
      kv_source = GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv

      # this will be the remaining implementation once the migration is complete
      cfg = GitHub::KV.config.dup
      cfg.table_name = Profiles::Kv::DataStore.table_name

      kv_target = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::Users.connection }

      flags = GitHub::Config::DualWriteKV::Flags.new(
        dual_read: :profiles_dual_read,
        dual_write: :profiles_dual_write,
        write_to_target: :profiles_write_to_target,
        log_mismatched_values: :profiles_log_mismatched_values,
      )
      @kv = GitHub::Config::DualWriteKV.new(owner: OWNER, kv_source:, kv_target:, flags:)
      @kv
    end
  end
end
