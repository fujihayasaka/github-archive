# typed: true
# frozen_string_literal: true

module FeatureManagement
  autoload :Client, "feature_management/client"
  autoload :FeatureFlagHubClient, "feature_management/feature_flag_hub_client"
  autoload :ClientError, "feature_management/client_error"
  autoload :FeatureFlagHubClientError, "feature_management/feature_flag_hub_client_error"
  autoload :ActorTenant, "feature_management/actor_tenant"

  autoload :CurrentUser, "feature_management/current_user"
  autoload :FeatureFlagHubClientUtil, "feature_management/feature_flag_hub_client_util"
  autoload :FeatureFlagHubFeatureManagementClient, "feature_management/feature_flag_hub_feature_management_client"
  autoload :FeatureFlagHubSegmentMemberManagementClient, "feature_management/feature_flag_hub_segment_member_management_client"
  autoload :FeatureFlagHubAsyncOperationError, "feature_management/feature_flag_hub_async_operation_error"
  autoload :FeatureFlagHubValidationError, "feature_management/feature_flag_hub_validation_error"
  autoload :FeatureFlagHubPreconditionFailedError, "feature_management/feature_flag_hub_precondition_failed_error"

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
end
