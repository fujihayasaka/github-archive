# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require_relative "k_v/data_store"

module AdvisoryDB
  module RepositoryAdvisories
    class KV
      OWNER = "github/repo_advisories"

      @kv = T.let(nil, T.nilable(GitHub::KV))

      sig { returns(GitHub::KV) }
      def self.store
        return @kv if @kv

        config = GitHub::KV.config.dup
        config.table_name = AdvisoryDB::RepositoryAdvisories::KV::DataStore.table_name

        GitHub::KV.new(config: config) { ApplicationRecord::Domain::RepositoriesCollab.connection }
      end
    end
  end
end
