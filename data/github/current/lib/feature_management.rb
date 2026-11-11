# typed: true
# frozen_string_literal: true

module FeatureManagement
  autoload :Client, "feature_management/client"
  autoload :FeatureFlagDataClient, "feature_management/feature_flag_data_client"
  autoload :ClientError, "feature_management/client_error"
  autoload :FeatureManagementLiteError, "feature_management/feature_management_lite_error"
  autoload :FeatureFlagDataClientError, "feature_management/feature_flag_data_client_error"
  autoload :ActorTenant, "feature_management/actor_tenant"
  autoload :CurrentUser, "feature_management/current_user"
  autoload :FeatureManagementLiteClient, "feature_management/feature_management_lite_client"

  module Core
    autoload :Operation, "feature_management/core/operation"
  end

  module Management
    autoload :CustomGates, "feature_management/management/custom_gates"
    autoload :PercentageOfActors, "feature_management/management/percentage_of_actors"
    autoload :PercentageOfCalls, "feature_management/management/percentage_of_calls"
    autoload :Node, "feature_management/management/node"
    autoload :FeatureFlag, "feature_management/management/feature_flag"
  end

  module Models
    autoload :DevtoolsFeature, "feature_management/models/devtools_feature"
    autoload :PaginatedDevtoolsActorsCollection, "feature_management/models/paginated_devtools_actors_collection"
    autoload :PaginatedDevtoolsFeaturesCollection, "feature_management/models/paginated_devtools_features_collection"
  end
end
