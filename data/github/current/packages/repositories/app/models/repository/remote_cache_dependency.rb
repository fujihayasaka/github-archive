# typed: true
# frozen_string_literal: true

module Repository::RemoteCacheDependency
  extend T::Helpers

  requires_ancestor { Repository }

  sig { params(event: Repositories::Cache::InvalidateOn).void }
  def invalidate_nwo_cache(event)
    return unless self.feature_flag_enabled?(:remote_cache_repo_invalidate, default: false)

    Repositories::Cache::ByNameAndOwnerClient.new(name, owner_id).invalidate(event.serialize)
  end
end
