# typed: true
# frozen_string_literal: true

module GitHub
  # Extension module to `GitHub::RemoteCache::Preset` that disables the cache
  # if there have been recent writes to specified database clusters.
  #
  # Example:
  #
  #   class Repositories::Cache::UserPermissionClient
  #     include GitHub::RemoteCache::Preset
  #     include GitHub::RemoteCache::Preset::DisableIfRecentDatabaseWrite
  #
  #     # Disable cache if there are tracked writes to certain database clusters
  #     sig { override.returns(T.nilable(T::Array[T.class_of(ApplicationRecord::Base)])) }
  #     def disable_on_writes_to
  #       [ApplicationRecord::Repositories]
  #     end
  #   end
  #
  module RemoteCache::Preset::DisableIfRecentDatabaseWrite
    extend T::Helpers

    abstract!

    sig { abstract.returns(T.nilable(T::Array[T.class_of(ApplicationRecord::Base)])) }
    def disable_on_writes_to; end

    sig { abstract.returns(T::Boolean) }
    def enabled?; end

    sig { abstract.returns(Symbol) }
    def cache_key_name; end

    sig { returns(T::Boolean) }
    def _internal_enabled?
      return false if outstanding_writes?
      super
    end

    private

    sig { abstract.returns(GitHub::RemoteCache::Client) }
    def cache_client; end

    sig { returns(T::Boolean) }
    def outstanding_writes?
      clusters_to_check = disable_on_writes_to
      return true unless clusters_to_check.present?

      replication_state = DatabaseSelector::ReplicationState.current
      return false unless replication_state

      outstanding_writes = replication_state.to_hash.keys.any? do |cluster_name|
        clusters_to_check.any? { |cluster_class| cluster_class.cluster_name == cluster_name }
      end

      if outstanding_writes
        tags = cache_client.base_metric_tags.dup
        tags.push("cache_key_name:#{cache_key_name}")

        if GitHub.context[:remote_call_source_datadog_tags]
          tags.concat(GitHub.context[:remote_call_source_datadog_tags])
        end

        # Pin the host tag to a constant, default value to reduce cardinality and cost of metric.
        # Also, manually add the current stamp tag since that was previously auto-added based on
        # the host tag.
        tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.stamp_tag)

        GitHub.dogstats.distribution("github.remote_cache.disable_on_db_write", 1, tags: tags)
      end

      outstanding_writes
    end
  end
end
