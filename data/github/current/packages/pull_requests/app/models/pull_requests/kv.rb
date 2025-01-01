# typed: true
# frozen_string_literal: true

require "github/config/kv_dual_write"

# ⚠️ WARNING:
# this module uses the same table as Issues::KV.
# All keys in this module should be prefixed with "pull_requests/" to avoid collisions.
# See: https://github.com/github/github-kv/issues/29 for more details.
module PullRequests
  module KV
    SHARD_KEY_COLUMN = :repository_id

    sig { params(repository: Repositories::IRepository).returns(GitHub::KV) }
    def self.for_repository(repository)
      config = GitHub::KV.config.dup
      config.table_name = :ipr_key_values
      config.shard_key_column = SHARD_KEY_COLUMN

      GitHub::KV.new(config:, shard_key_value: repository.id) do
        ApplicationRecord::Domain::IssuesPullRequests.connection
      end
    end

    sig do
      params(
        repository: Repositories::IRepository,
        feature_flag_prefix: Symbol,
        key_transformer: T.nilable(GitHub::Config::DualWriteKV::IKeyTransformer),
      ).returns(GitHub::Config::DualWriteKV)
    end
    def self.dual_write_for_repository(repository, feature_flag_prefix:, key_transformer: nil)
      GitHub::Config::DualWriteKV.new(
        owner: "github/pull_requests",
        kv_source: GitHub.kv, # rubocop:todo GitHub/DoNotUseGlobalKv
        kv_target: PullRequests::KV.for_repository(repository),
        flags: GitHub::Config::DualWriteKV::Flags.with_prefix(feature_flag_prefix),
        shard_key_column: SHARD_KEY_COLUMN,
        shard_key_value: repository.id,
        key_transformer:,
      )
    end
  end
end
