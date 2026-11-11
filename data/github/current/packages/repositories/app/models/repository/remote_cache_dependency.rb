# typed: true
# frozen_string_literal: true

module Repository::RemoteCacheDependency
  extend T::Helpers

  requires_ancestor { Repository }

  sig { params(event: Repositories::Cache::InvalidateOn).void }
  def invalidate_nwo_cache(event = Repositories::Cache::InvalidateOn::Updated)
    return if owner_id.nil? || name.nil?
    return unless self.feature_flag_enabled?(:remote_cache_repo_invalidate, default: false)

    if self.feature_flag_enabled?(:remote_cache_repo_write_thru, default: false)
      Repositories::Cache::ByNameAndOwnerClient.new(name, owner_id).store(T.cast(self, Repository)) # rubocop:disable GitHub/AvoidCast
      Repositories::Cache::ByQualifiedNameClient.new("#{owner_display_login}/#{name}").store(T.cast(self, Repository)) # rubocop:disable GitHub/AvoidCast
      Repositories::Cache::ByIdClient.new(id).store(T.cast(self, Repository)) # rubocop:disable GitHub/AvoidCast
    else
      Repositories::Cache::ByNameAndOwnerClient.new(name, owner_id).invalidate(event.serialize)
      Repositories::Cache::ByQualifiedNameClient.new("#{owner_display_login}/#{name}").invalidate(event.serialize)
      Repositories::Cache::ByIdClient.new(id).invalidate(event.serialize)
    end
  end
end
