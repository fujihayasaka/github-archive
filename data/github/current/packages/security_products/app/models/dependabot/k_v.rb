# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "k_v/data_store"

module Dependabot
  class KV
    OWNER = "github/dependabot"

    @kv = T.let(nil, T.nilable(GitHub::Config::DualWriteKV))

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.store
      return @kv if @kv

      # this is a temporary exemption until the data is migrated to the new table
      kv_source = GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv

      config = GitHub::KV.config.dup
      config.table_name = Dependabot::KV::DataStore.table_name

      kv_target = GitHub::KV.new(config:) { ApplicationRecord::Domain::RepositoriesNotify.connection }

      flags = GitHub::Config::DualWriteKV::Flags.new(
        dual_read: :dependabot_dual_read,
        dual_write: :dependabot_dual_write,
        write_to_target: :dependabot_write_to_target,
      )

      GitHub::Config::DualWriteKV.new(owner: OWNER, kv_source:, kv_target:, flags:)
    end
  end
end
