# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::RepositoryWithNetworkSerializer
    extend T::Generic
    extend GitHub::RemoteCache::Serializer
    extend Cache::RepositorySerialization

    CachedType = type_template { { fixed: T.nilable(IRepository) } }

    sig { override.params(object: CachedType).returns(Object) }
    def self.serialize(object)
      return if object.nil?

      # We already eager loaded the network association on repo lookup, so store it in its own cache key
      Repositories::Cache::NetworkByIdClient.new(object.network_id).store(object.network)

      {
        "repository" => object.attributes_before_type_cast,
        "internal_repository" => object.internal_repository&.attributes_before_type_cast || {},
        "network_privilege" => object.network_privilege&.attributes_before_type_cast || {},
      }
    end

    sig { override.params(cached_value: Object).returns(CachedType) }
    def self.deserialize(cached_value)
      return if cached_value.blank?

      repo = deserialize_repository(cached_value)
      return if repo.nil?

      cached_value = T.cast(cached_value, T::Hash[String, T.untyped])

      # Try to fetch the network from the cache. If we're in shadow mode we're always going to fetch from the DB
      # for comparison
      network = Repositories::Cache::NetworkByIdClient.new(repo.network_id).fetch do
        repo.network
      end
      GitHub::PrefillAssociations.prefill_association(repo, :network, T.cast(network, RepositoryNetwork)) # rubocop:todo GitHub/AvoidCast

      internal = InternalRepository.instantiate(cached_value["internal_repository"]) if cached_value["internal_repository"].present?
      GitHub::PrefillAssociations.prefill_association(repo, :internal_repository, internal)

      network_privilege = Stafftools::NetworkPrivilege.instantiate(cached_value["network_privilege"]) if cached_value["network_privilege"].present?
      GitHub::PrefillAssociations.prefill_association(repo, :network_privilege, network_privilege)

      repo
    end

    sig { override.params(cached_value: T.nilable(CachedType), db_value: T.nilable(CachedType)).returns(GitHub::RemoteCache::Comparison) }
    def self.compare(cached_value, db_value)
      cached_attr, db_attr = normalize_repository(cached_value, db_value)

      [[cached_value, cached_attr], [db_value, db_attr]].each do |obj, attrs|
        attrs["internal_repository"] = obj.internal_repository&.attributes_before_type_cast if obj&.internal_repository
        attrs["network_privilege"] = obj.network_privilege&.attributes_before_type_cast if obj&.network_privilege
      end

      compare_repository(cached_attr, db_attr)
    end
  end
end
