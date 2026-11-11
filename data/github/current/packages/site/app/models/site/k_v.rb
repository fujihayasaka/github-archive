# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Site
  class KV
    OWNER = "github/marketing_publishing_pipeline"
    MAX_KEY_LENGTH = GitHub::KV::MAX_KEY_LENGTH

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Site::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Site.connection }
    end
  end
end
