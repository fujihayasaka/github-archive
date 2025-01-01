# typed: true
# frozen_string_literal: true

# ⚠️ WARNING:
# this module uses the same table as PullRequests::KV.
# All keys in this module should be prefixed with "issues/" to avoid collisions.
# See: https://github.com/github/github-kv/issues/29 for more details.
module Issues
  module KV
    SHARD_KEY_COLUMN = :repository_id

    sig { params(repository: Repositories::IRepository).returns(GitHub::KV) }
    def self.for_repository(repository)
      raise ArgumentError, "Cannot use Issues::KV without a persisted Repository" unless repository.id

      for_repository_id(T.must(repository.id))
    end

    sig { params(repository_id: Integer).returns(GitHub::KV) }
    def self.for_repository_id(repository_id)
      config = GitHub::KV.config.dup
      config.table_name = :ipr_key_values
      config.shard_key_column = SHARD_KEY_COLUMN

      GitHub::KV.new(config:, shard_key_value: repository_id) do
        ApplicationRecord::Domain::IssuesPullRequests.connection
      end
    end

    sig { returns(GitHub::KV) }
    def self.store
      config = GitHub::KV.config.dup
      config.table_name = :ipr_key_values

      GitHub::KV.new(config:) do
        ApplicationRecord::Domain::IssuesPullRequests.connection
      end
    end
  end
end
