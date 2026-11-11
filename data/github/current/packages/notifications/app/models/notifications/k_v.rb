# typed: strict
# frozen_string_literal: true

require "github/config/kv_dual_write"

module Notifications
  class KV
    OWNER = "github/notifications"

    sig { returns(GitHub::KV) }
    def self.store
      @store ||= T.let(build_store, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.build_store
      config = GitHub::KV.config.dup
      config.table_name = :notification_key_values

      GitHub::KV.new(config: config) do
        ApplicationRecord::Domain::Notifications.connection
      end
    end
  end
end
