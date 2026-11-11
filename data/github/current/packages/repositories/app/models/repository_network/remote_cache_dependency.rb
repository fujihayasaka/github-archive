# typed: true
# frozen_string_literal: true

class RepositoryNetwork
  module RemoteCacheDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { RepositoryNetwork }

    included do
      sig { params(event: Repositories::Cache::InvalidateOn).void }
      def invalidate_network_by_id_cache(event = Repositories::Cache::InvalidateOn::Updated)
        return if id.nil?

        network = T.cast(self, RepositoryNetwork)
        return unless network.feature_flag_enabled?(:remote_cache_repo_invalidate, default: false)

        client = Repositories::Cache::NetworkByIdClient.new(id)
        # Only update the cache if there are no unpersisted changes
        if (network.persisted? && !network.changed?) && network.feature_flag_enabled?(:remote_cache_repo_write_thru, default: false)
          client.store(network)
        else
          client.invalidate(event.serialize)
        end
      end
    end

    class_methods do
      sig { params(network_id: Integer, event: Repositories::Cache::InvalidateOn).void }
      def invalidate_network_by_id_cache(network_id, event = Repositories::Cache::InvalidateOn::Updated)
        return if network_id.nil?

        network = RepositoryNetwork.new(id: network_id)
        network.invalidate_network_by_id_cache(event)
      end
    end
  end
end
