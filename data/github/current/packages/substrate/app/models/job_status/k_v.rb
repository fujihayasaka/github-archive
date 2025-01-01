# typed: strict
# frozen_string_literal: true

require_relative "data_store"

class JobStatus
  class KV
    OWNER = "github/monolith-platform"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = JobStatus::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::UsersBallast.connection }
    end
  end
end
