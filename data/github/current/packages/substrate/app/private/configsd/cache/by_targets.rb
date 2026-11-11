# typed: strict
# frozen_string_literal: true

class Configsd::Cache::ByTargets < Configsd::Cache::ByTarget
  SourceKeyType = type_member { { fixed: Configurations::RepoOwnershipChain } }
  SourceValueType = type_member { { fixed: T.nilable(Configurations::ResolvedConfigEntries) } }

  sig { override.returns(T::Boolean) }
  def enabled?
    GH.feature_flag_enabled?(:remote_cache_configs_batch_enabled)
  end

  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if GH.feature_flag_enabled?(:remote_cache_configs_batch_shadow_mode)
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    end
  end
end
