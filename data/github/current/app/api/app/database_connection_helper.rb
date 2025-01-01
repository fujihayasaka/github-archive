# typed: true
# frozen_string_literal: true

module Api::App::DatabaseConnectionHelper
  def with_replica_clusters(clusters, current_user: nil, feature_flag: nil, &block)
    return block.call if ActiveRecord::Base.single_database_cluster?

    if feature_flag
      if current_user&.feature_flag_enabled_or_raise?(feature_flag) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        ActiveRecord::Base.connected_to_many(clusters, role: :reading) do
          block.call
        end
      else
        block.call
      end
    else
      ActiveRecord::Base.connected_to_many(clusters, role: :reading) do
        block.call
      end
    end
  end
end
