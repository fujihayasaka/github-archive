# typed: true
# frozen_string_literal: true

module PackageRegistry
  module Twirp
    module ActionPackages
      class Client < PackageRegistry::Twirp::BaseClient
        extend T::Sig

        def initialize(connection_open_timeout: CONNECTION_OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
          super(package_registry_hmac_key: GitHub.package_registry_action_packages_hmac_key,
            connection_open_timeout: connection_open_timeout, read_timeout: read_timeout)
        end

        sig do
          params(
            action_references: T::Array[{
              namespace: String,
              name: String,
              semver_ref: String
            }],
            workflow_repo_id: T.nilable(Integer),
            anonymous: T.nilable(T::Boolean)
          ).returns(
            Proto::RegistryMetadata::V1::ActionPackages::ResolveActionPackageVersionsResponse)
        end
        def resolve_action_packages(action_references:, workflow_repo_id: nil, anonymous: false)
          raise ArgumentError, "workflow_repo_id must be provided when anonymous is false" if !anonymous && workflow_repo_id.nil?
          raise ArgumentError, "workflow_repo_id must not be provided when anonymous is true" if anonymous && !workflow_repo_id.nil?

          rpc(:ResolveActionPackages, workflow_repo_id: workflow_repo_id, anonymous_request: anonymous, actions: action_references)
        end

        sig do
          params(
            action_references: T::Array[{
              namespace: String,
              name: String,
              semver_ref: String
            }]
          ).returns(
            Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageVersionsMetadataResponse)
        end
        def get_action_package_versions_metadata(action_references:)
          rpc(:GetActionPackageVersionsMetadata, versions: action_references)
        end

        sig do
          params(
            package_id: Integer
          ).returns(
            Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse)
        end
        def get_action_package_resolution_settings(package_id:)
          rpc(:GetActionPackageResolutionSettings, package_id: package_id)
        end

        sig do
          params(
            package_id: Integer
          ).returns(
            Proto::RegistryMetadata::V1::ActionPackages::ActivateActionPackageResolutionResponse)
        end
        def activate_action_package_resolution(package_id:)
          rpc(:ActivateActionPackageResolution, package_id: package_id)
        end

        def twirp_class
          Proto::RegistryMetadata::V1::ActionPackages::ActionPackagesServiceClient
        end

        sig do
          params(
            package_id: Integer,
            sharing_policy: Integer,
          ).returns(
            Proto::RegistryMetadata::V1::ActionPackages::UpdateActionPackageSharingPolicyResponse)
        end
        def update_action_package_resolution_settings(package_id:, sharing_policy:)
          rpc(:UpdateActionPackageSharingPolicy, package_id: package_id, sharing_policy: sharing_policy)
        end
      end
    end
  end
end
