# typed: true
# frozen_string_literal: true

module Api::App::DatabaseConnectionHelper
  def with_replica_clusters(clusters, current_user: nil, feature_flag: nil, &block)
    if feature_flag
      if current_user&.feature_enabled?(feature_flag)
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
