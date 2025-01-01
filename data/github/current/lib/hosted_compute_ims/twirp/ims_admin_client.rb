# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class AdminClient < HostedComputeIms::Twirp::BaseClient
      sig do
        returns(TwirpResponse)
      end
      def list_curated_image_definitions
        rpc(
          :ListCuratedImageDefinitions,
          {}
        )
      end

      sig do
        params(
          image_definition_id: Integer
        ).returns(TwirpResponse)
      end
      def get_curated_image_definition(image_definition_id:)
        rpc(
          :GetCuratedImageDefinition,
          image_definition_id: image_definition_id
        )
      end

      sig do
        params(
          image_definition_id: Integer
        ).returns(TwirpResponse)
      end
      def list_curated_image_versions(image_definition_id:)
        rpc(
          :ListCuratedImageVersions,
          image_definition_id: image_definition_id
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          version: String
        ).returns(TwirpResponse)
      end
      def get_curated_image_version(image_definition_id:, version:)
        rpc(
          :GetCuratedImageVersion,
          image_definition_id: image_definition_id,
          version: version
        )
      end

      sig do
        params(
          name: String,
          owner_id: String,
          os_type: Integer,
          architecture: Integer,
          enabled: T::Boolean,
          feature_flag: String,
          is_image_generation_supported: T::Boolean
        ).returns(TwirpResponse)
      end
      def create_curated_image_definition(name:, owner_id:, os_type:, architecture:, enabled:, feature_flag:, is_image_generation_supported:)
        rpc(
          :CreateCuratedImageDefinition,
          name: name,
          owner_id: owner_id,
          os_type: os_type,
          architecture: architecture,
          enabled: enabled,
          feature_flag: feature_flag,
          is_image_generation_supported: is_image_generation_supported
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          version: String,
          source_vhd_url: String,
          enabled: T::Boolean,
          vm_generation: T.nilable(Symbol),
          os_state: T.nilable(Symbol),
          azure_purchase_plan: T.nilable(String),
          agent_user: T.nilable(String)
        ).returns(TwirpResponse)
      end
      def create_curated_image_version(image_definition_id:, version:, source_vhd_url:, enabled:, vm_generation: nil, os_state: nil, azure_purchase_plan: nil, agent_user: nil)
        rpc(
          :CreateCuratedImageVersion,
          image_definition_id: image_definition_id,
          version: version,
          source_vhd_url: source_vhd_url,
          enabled: enabled,
          vm_generation: vm_generation,
          os_state: os_state,
          azure_purchase_plan: azure_purchase_plan,
          agent_user: agent_user
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          name: String,
          enabled: T::Boolean,
          feature_flag: String,
          is_image_generation_supported: T::Boolean
        ).returns(TwirpResponse)
      end
      def update_curated_image_definition(image_definition_id:, name:, enabled:, feature_flag:, is_image_generation_supported:)
        rpc(
          :UpdateCuratedImageDefinition,
          image_definition_id: image_definition_id,
          name: name,
          enabled: enabled,
          feature_flag: feature_flag,
          is_image_generation_supported: is_image_generation_supported
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          version: String,
          enabled: T::Boolean
        ).returns(TwirpResponse)
      end
      def update_curated_image_version(image_definition_id:, version:, enabled:)
        rpc(
          :UpdateCuratedImageVersion,
          image_definition_id: image_definition_id,
          version: version,
          enabled: enabled
        )
      end

      sig do
        params(
          image_definition_id: Integer
        ).returns(TwirpResponse)
      end
      def delete_curated_image_definition(image_definition_id:)
        rpc(
          :DeleteCuratedImageDefinition,
          image_definition_id: image_definition_id
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          version: String,
        ).returns(TwirpResponse)
      end
      def delete_curated_image_version(image_definition_id:, version:)
        rpc(
          :DeleteCuratedImageVersion,
          image_definition_id: image_definition_id,
          version: version
        )
      end

      sig do
        params(
          name: String,
          owner_id: String,
          points_to_image_definition_id: Integer,
          enabled: T::Boolean,
          feature_flag: String,
          is_image_generation_supported: T::Boolean
        ).returns(TwirpResponse)
      end
      def create_curated_image_definition_pointer(name:, owner_id:, points_to_image_definition_id:, enabled:, feature_flag:, is_image_generation_supported:)
        rpc(
          :CreateCuratedImageDefinitionPointer,
          name: name,
          owner_id: owner_id,
          points_to_image_definition_id: points_to_image_definition_id,
          enabled: enabled,
          feature_flag: feature_flag,
          is_image_generation_supported: is_image_generation_supported
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          name: String,
          points_to_image_definition_id: Integer,
          enabled: T::Boolean,
          feature_flag: String,
          is_image_generation_supported: T::Boolean
        ).returns(TwirpResponse)
      end
      def update_curated_image_definition_pointer(image_definition_id:, name:, points_to_image_definition_id:, enabled:, feature_flag:, is_image_generation_supported:)
        rpc(
          :UpdateCuratedImageDefinitionPointer,
          image_definition_id: image_definition_id,
          name: name,
          points_to_image_definition_id: points_to_image_definition_id,
          enabled: enabled,
          feature_flag: feature_flag,
          is_image_generation_supported: is_image_generation_supported
        )
      end

      sig do
        params(
          image_definition_id: Integer
        ).returns(TwirpResponse)
      end
      def delete_curated_image_definition_pointer(image_definition_id:)
        rpc(
          :DeleteCuratedImageDefinitionPointer,
          image_definition_id: image_definition_id
        )
      end

      sig { returns(T.class_of(GitHub::HostedComputeIms::AdminApi::ImageManagementAdminServiceClient)) }
      def twirp_class
        GitHub::HostedComputeIms::AdminApi::ImageManagementAdminServiceClient
      end
    end
  end
end
