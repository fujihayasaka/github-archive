# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"
require "github/enterprise_accounts/kv/data_store"

module EnterpriseAccounts
  class KV
    OWNER = "github/enterprise_accounts"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = EnterpriseAccounts::KV::DataStore.table_name
      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Users.connection }
    end
  end
end
