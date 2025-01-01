# typed: strict
# frozen_string_literal: true

module Launch
  module Twirp
    class LargerRunnersClient < Launch::Twirp::BaseClient

      OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }
      Entity = T.type_alias { BaseClient::Entity }

      # Pools

      sig do
        params(
          owner: OrgOrEnterprise,
          image: Actions::LargerRunner::ImageKey,
          name: T.nilable(String),
          platform: T.nilable(String),
          runner_group_id: Integer,
          maximum_runners: Integer,
          machine_spec_id: T.nilable(String),
          image_sas_uri: T.nilable(String),
          labels: T.nilable(T::Array[String]),
          is_public_ip_enabled: T.nilable(T::Boolean),
          persistent_os_disk: T.nilable(T::Boolean)
        ).returns(TwirpResponse)
      end
      def create_pool(owner, image:, name:, platform:, runner_group_id:, maximum_runners:, machine_spec_id:, image_sas_uri:, labels: [], is_public_ip_enabled: false, persistent_os_disk: false)
        enforce_larger_runners_enabled!(owner)

        launch_image = GitHub::Launch::Services::Largerrunners::ImageKey.new
        launch_image.source = image.source
        launch_image.id = image.id
        launch_image.version = image.version

        request = GitHub::Launch::Services::Largerrunners::CreatePoolRequest.new(
          owner_id: identity(owner),
          name: name,
          platform: platform,
          runner_group_id: runner_group_id,
          labels: labels,
          image: launch_image,
          machine_spec_id: machine_spec_id,
          is_public_ip_enabled: is_public_ip_enabled,
          image_sas_uri: image_sas_uri,
          maximum_runners: maximum_runners,
          persistent_os_disk: persistent_os_disk,
        )

        rescue_rpc { client.create_pool(request) }
      end

      sig { params(owner: OrgOrEnterprise, pool_id: Integer).returns(TwirpResponse) }
      def get_pool(owner, pool_id:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::GetPoolRequest.new(
          owner_id: identity(owner),
          pool_id: pool_id,
        )

        rescue_rpc { client.get_pool(request) }
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          pool_id: Integer,
          runner_group_id: Integer,
          name: T.nilable(String),
          labels: T::Array[String],
          maximum_runners: Integer,
          machine_spec_id: T.nilable(String),
          is_public_ip_enabled: T::Boolean,
          image: Actions::LargerRunner::ImageKey,
        ).returns(TwirpResponse)
      end
      def update_pool(owner, pool_id:, runner_group_id:, name:, labels:, maximum_runners:, machine_spec_id:, is_public_ip_enabled:, image:)
        enforce_larger_runners_enabled!(owner)

        launch_image = GitHub::Launch::Services::Largerrunners::ImageKey.new(id: image.id, source: image.source, version: image.version)

        # TODO we need to ensure that the update calls can pass in null strings or we recreate the images
        request = GitHub::Launch::Services::Largerrunners::UpdatePoolRequest.new(
          owner_id: identity(owner),
          pool_id: pool_id,
          name: name,
          runner_group_id: runner_group_id,
          labels: labels,
          machine_spec_id: machine_spec_id,
          is_public_ip_enabled: is_public_ip_enabled,
          maximum_runners: maximum_runners,
          image: launch_image,
        )

        rescue_rpc { client.update_pool(request) }
      end

      sig { params(owner: OrgOrEnterprise, pool_id: Integer).returns(TwirpResponse) }
      def delete_pool(owner, pool_id:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::DeletePoolRequest.new(
          owner_id: identity(owner),
          pool_id: pool_id,
        )

        rescue_rpc { client.delete_pool(request) }
      end

      # Image Versions

      sig { params(owner: OrgOrEnterprise, image_definition_id: Integer, image_sas_uri: String).returns(TwirpResponse) }
      def create_image_version(owner, image_definition_id:, image_sas_uri:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::CreateImageVersionRequest.new(
          owner_id: identity(owner),
          image_definition_id: image_definition_id,
          image_sas_uri: image_sas_uri,
        )

        rescue_rpc { client.create_image_version(request) }
      end

      sig { params(owner: OrgOrEnterprise, image_definition_id: Integer, image_version: String).returns(TwirpResponse) }
      def get_image_version(owner, image_definition_id:, image_version:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::GetImageVersionRequest.new(
          owner_id: identity(owner),
          image_definition_id: image_definition_id,
          image_version: image_version,
        )

        rescue_rpc { client.get_image_version(request) }
      end

      sig { params(owner: OrgOrEnterprise, image_definition_id: Integer, image_version: String).returns(TwirpResponse) }
      def delete_image_version(owner, image_definition_id:, image_version:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::DeleteImageVersionRequest.new(
          owner_id: identity(owner),
          image_definition_id: image_definition_id,
          image_version: image_version,
        )

        rescue_rpc { client.delete_image_version(request) }
      end

      sig { params(owner: OrgOrEnterprise, image_definition_id: Integer).returns(TwirpResponse) }
      def get_image_definition(owner, image_definition_id:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::GetImageDefinitionRequest.new(
          owner_id: identity(owner),
          image_definition_id: image_definition_id,
        )

        rescue_rpc { client.get_image_definition(request) }
      end

      sig { params(owner: OrgOrEnterprise, image_definition_id: Integer).returns(TwirpResponse) }
      def delete_image_definition(owner, image_definition_id:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::DeleteImageDefinitionRequest.new(
          owner_id: identity(owner),
          image_definition_id: image_definition_id,
        )

        rescue_rpc { client.delete_image_definition(request) }
      end

      # Lists

      sig { params(owner: OrgOrEnterprise).returns(TwirpResponse) }
      def list_curated_images(owner)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListCuratedImagesRequest.new(
          owner_id: identity(owner),
        )

        rescue_rpc { client.list_curated_images(request) }
      end

      sig { params(owner: OrgOrEnterprise).returns(TwirpResponse) }
      def list_image_definitions(owner)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListImageDefinitionsRequest.new(
          owner_id: identity(owner),
        )

        rescue_rpc { client.list_image_definitions(request) }
      end

      sig { params(owner: OrgOrEnterprise, image_definition_id: Integer, pattern: T.nilable(String)).returns(TwirpResponse) }
      def list_image_versions(owner, image_definition_id:, pattern: nil)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListImageVersionsRequest.new(
          owner_id: identity(owner),
          image_definition_id: image_definition_id
        )

        rescue_rpc { client.list_image_versions(request) }
      end

      sig { params(owner: OrgOrEnterprise).returns(TwirpResponse) }
      def list_labels(owner)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListLabelsRequest.new(
          owner_id: identity(owner),
        )

        rescue_rpc { client.list_labels(request) }
      end

      sig { params(owner: OrgOrEnterprise).returns(TwirpResponse) }
      def list_machine_specs(owner)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListMachineSpecsRequest.new(
          owner_id: identity(owner),
        )

        rescue_rpc { client.list_machine_specs(request) }
      end

      sig { params(owner: OrgOrEnterprise).returns(TwirpResponse) }
      def list_marketplace_images(owner)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListMarketplaceImagesRequest.new(
          owner_id: identity(owner),
        )

        rescue_rpc { client.list_marketplace_images(request) }
      end

      sig { params(owner: OrgOrEnterprise, pool_id: Integer).returns(TwirpResponse) }
      def list_pool_agents(owner, pool_id:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListPoolAgentsRequest.new(
          owner_id: identity(owner),
          pool_id: pool_id,
        )

        rescue_rpc { client.list_pool_agents(request) }
      end

      sig { params(owner: OrgOrEnterprise, entity: Entity, is_public_ip_enabled: T.nilable(T::Boolean)).returns(TwirpResponse) }
      def list_pools(owner, entity:, is_public_ip_enabled: nil)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListPoolsRequest.new(
          entity_id: identity(entity),
          owner_id: identity(owner),
          plan_owner_id: identity(plan_owner_for(owner)),
          entity_is_private: !(entity.is_a?(Repository) && entity.public)
        )

        request.is_public_ip_enabled = Google::Protobuf::BoolValue.new(value: is_public_ip_enabled) unless is_public_ip_enabled.nil?

        rescue_rpc { client.list_pools(request) }
      end

      sig { params(owner: OrgOrEnterprise).returns(TwirpResponse) }
      def get_tenant_info(owner)
        # skip enforcing larger runners enabled because this endpoint doesn't call Runner service

        request = GitHub::Launch::Services::Largerrunners::GetTenantInfoRequest.new(
          owner_id: identity(owner),
        )

        rescue_rpc { client.get_tenant_info(request) }
      end

      sig { params(owner: OrgOrEnterprise).returns(TwirpResponse) }
      def list_beta_features(owner)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::ListBetaFeaturesRequest.new(
          owner_id: identity(owner),
        )

        rescue_rpc { client.list_beta_features(request) }
      end

      sig { params(owner: OrgOrEnterprise, feature_name: String).returns(TwirpResponse) }
      def get_beta_feature(owner, feature_name:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::GetBetaFeatureRequest.new(
          owner_id: identity(owner),
          feature_name: feature_name
        )

        rescue_rpc { client.get_beta_feature(request) }
      end

      sig { params(owner: OrgOrEnterprise, feature_name: String, enabled: T::Boolean).returns(TwirpResponse) }
      def set_beta_feature(owner, feature_name:, enabled:)
        enforce_larger_runners_enabled!(owner)

        request = GitHub::Launch::Services::Largerrunners::SetBetaFeatureRequest.new(
          owner_id: identity(owner),
          feature_name: feature_name,
          enabled: enabled
        )

        rescue_rpc { client.set_beta_feature(request) }
      end

      private

      sig { params(owner: OrgOrEnterprise).void }
      def enforce_larger_runners_enabled!(owner)
        unless is_owner_or_parent_onboarded?(owner)
          # If this exception is raised, it means that we are performing a request to the Larger Runners service for an entity which is not onboarded yet.
          # We shouldn't allow this because it will cause an unexpected host fault-in in the Runner service.
          raise "Failed to perform request to Larger Runners service. Entity is not onboarded to Larger Runners"
        end

        # For organizations which belongs to business there are could be 3 cases:
        # 1. Both organization and business are onboarded
        # 2. Only organization is onboarded
        # 3. Only business is onboarded
        # For #2 and #3 cases, we should synchronize onboarding state between organization and business to make sure that both of them are marked as onboarded
        # We need it because we use onboarding status to iterate through onboarded accounts so we need to know what exact organizations in business are onboarded
        # It is also required to handle use-cases when org is moved in / out of business to make sure that org won't lose existing runners
        if owner.is_a?(Organization) && owner.business.present?
          actor = User.ghost
          owner.onboard_larger_runners(actor: actor)
          T.must(owner.business).onboard_larger_runners(actor: actor)
        end
      end

      sig { params(owner: OrgOrEnterprise).returns(T::Boolean) }
      def is_owner_or_parent_onboarded?(owner)
        return true if owner.is_larger_runners_onboarded?

        if owner.is_a?(Organization) && owner.business.present?
          return true if T.must(owner.business).is_larger_runners_onboarded?
        end

        false
      end

      sig { params(owner: OrgOrEnterprise).returns(OrgOrEnterprise) }
      def plan_owner_for(owner)
        return owner unless owner.is_a? Organization

        business = owner.business
        return business if business.present?

        owner
      end

      sig { returns(T.class_of(GitHub::Launch::Services::Largerrunners::LargerRunnersClient)) }
      def twirp_class
        GitHub::Launch::Services::Largerrunners::LargerRunnersClient
      end
    end
  end
end
