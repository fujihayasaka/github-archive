# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::RepositorySerializer
    extend T::Generic
    extend GitHub::RemoteCache::Serializer

    CachedType = type_template { { fixed: T.nilable(IRepository) } }

    UNSTABLE_ATTRIBUTES = T.let(
      %w[
        primary_language_name_id
        public_fork_count
        raw_data
        watcher_count
      ].freeze, T::Array[String]
    )

    UNSTABLE_NETWORK_ATTRIBUTES = T.let(
      %w[
        disk_usage
        last_maintenance_at
        last_maintenance_attempted_at
        maintenance_count_since_full
        maintenance_status
        pushed_at
        pushed_count
        pushed_count_since_maintenance
        unpacked_size_in_mb
        updated_at
      ].freeze, T::Array[String]
    )

    sig { override.params(object: CachedType).returns(Object) }
    def self.serialize(object)
      return if object.nil?

      {
        "repository" => object.attributes_before_type_cast,
        "network" => object.network&.attributes_before_type_cast || {},
        "internal_repository" => object.internal_repository&.attributes_before_type_cast || {}
      }
    end

    sig { override.params(cached_value: Object).returns(CachedType) }
    def self.deserialize(cached_value)
      return if cached_value.blank?

      cached_value = T.cast(cached_value, T::Hash[String, T.untyped])
      repo = Repository.instantiate(cached_value["repository"]) if cached_value["repository"]
      return if repo.nil?

      network = RepositoryNetwork.instantiate(cached_value["network"]) if cached_value["network"].present?
      internal = InternalRepository.instantiate(cached_value["internal_repository"]) if cached_value["internal_repository"].present?

      if network
        GitHub::PrefillAssociations.prefill_associations(repo, :network, available_records: [network])
      else
        repo.association(:network).target = nil # rubocop:disable GitHub/DontCallAssociationTargetEquals
      end

      if internal
        GitHub::PrefillAssociations.prefill_associations(repo, :internal_repository, available_records: [internal])
      else
        repo.association(:internal_repository).target = nil # rubocop:disable GitHub/DontCallAssociationTargetEquals
      end

      repo
    end

    sig { override.params(cached_value: T.nilable(CachedType), db_value: T.nilable(CachedType)).returns(GitHub::RemoteCache::Comparison) }
    def self.compare(cached_value, db_value)
      cached_attr = cached_value&.attributes_before_type_cast || {}
      db_attr = db_value&.attributes_before_type_cast || {}

      ignore = FeatureFlag.vexi.enabled?(:remote_cache_repo_ignore_unstable_attrs, default: false)
      if ignore
        T.unsafe(cached_attr).except!(*UNSTABLE_ATTRIBUTES)
        T.unsafe(db_attr).except!(*UNSTABLE_ATTRIBUTES)
      end

      [[cached_value, cached_attr], [db_value, db_attr]].each do |obj, attrs|
        if obj&.network
          network_attrs = obj.network&.attributes_before_type_cast
          if network_attrs && ignore
            T.unsafe(network_attrs).except!(*UNSTABLE_NETWORK_ATTRIBUTES)
          end
          attrs["network"] = network_attrs
        end
        attrs["internal_repository"] = obj.internal_repository&.attributes_before_type_cast if obj&.internal_repository
      end

      GitHub::RemoteCache::Comparison.new(Hashdiff.diff(cached_attr, db_attr))
    end
  end
end
