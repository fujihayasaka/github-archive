# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::RepositoryWithNetworkSerializer
    extend T::Generic
    extend GitHub::RemoteCache::Serializer
    extend Cache::RepositorySerialization

    SourceValueType = type_template { { fixed: T.nilable(IRepository) } }

    sig { override.params(object: SourceValueType).returns(Object) }
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

    sig { override.params(cache_value: Object).returns(SourceValueType) }
    def self.deserialize(cache_value)
      return if cache_value.blank?

      repo = deserialize_repository(cache_value)
      return if repo.nil?

      cache_value = T.cast(cache_value, T::Hash[String, T.untyped])

      # Try to fetch the network from the cache. If we're in shadow mode we're always going to fetch from the DB
      # for comparison
      network = Repositories::Cache::NetworkByIdClient.new(repo.network_id).fetch do
        repo.network
      end
      GitHub::PrefillAssociations.prefill_association(repo, :network, T.cast(network, RepositoryNetwork)) # rubocop:todo GitHub/AvoidCast

      internal = InternalRepository.instantiate(cache_value["internal_repository"]) if cache_value["internal_repository"].present?
      GitHub::PrefillAssociations.prefill_association(repo, :internal_repository, internal)

      network_privilege = Stafftools::NetworkPrivilege.instantiate(cache_value["network_privilege"]) if cache_value["network_privilege"].present?
      GitHub::PrefillAssociations.prefill_association(repo, :network_privilege, network_privilege)

      repo
    end
  end
end
