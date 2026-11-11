# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Pages
  class KV
    OWNER = "github/pages"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Pages::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Pages.connection }
    end
  end
end
