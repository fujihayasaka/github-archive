# typed: true
# frozen_string_literal: true

module GitAuth
  class Store
    sig { returns(String) }
    attr_reader :id

    sig { returns(Stores::Store) }
    attr_reader :store

    sig { params(id: String).returns(T.nilable(GitAuth::Store)) }
    def self.from_id(id)
      store = Stores.domain.by_id(id)
      return nil unless store

      new(store)
    end

    sig { params(store: Stores::Store).void }
    def initialize(store)
      @store = T.let(store, Stores::Store)
      @id = T.let(store.id, String)
    end

    delegate :rpc, :dgit_read_routes, :dgit_write_routes, :dgit_delegate_for_update_refs_coordinator,
             :coalesce_dgit_updates?, :hash_algo, :original_shard_path, :spokes_id,
             :feature_flag_enabled_or_raise?, to: :store

    sig { returns(T::Boolean) }
    def nil?
      false
    end

    sig { returns(String) }
    def full_name
      store.id
    end
  end
end
