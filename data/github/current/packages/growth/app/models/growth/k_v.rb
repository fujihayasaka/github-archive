# typed: strict
# frozen_string_literal: true

module Growth
  class KV
    sig { returns(GitHub::KV) }
    def self.store
      @store ||= T.let(build_store, T.nilable(GitHub::KV))
    end

    sig { returns(GitHub::KV) }
    def self.build_store
      config = GitHub::KV.config.dup
      config.table_name = :growth_notice_key_values

      GitHub::KV.new(config: config) do
        ::ApplicationRecord::Domain::UsersCollab.connection
      end
    end
  end
end
