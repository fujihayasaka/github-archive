# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class AdminClient < HostedComputeIms::Twirp::BaseClient
      def initialize
        super(base_url: GitHub.hosted_compute_ims_url_curated)
      end

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
          os_type: Integer,
          architecture: Integer,
          enabled: T::Boolean,
          feature_flag: String
        ).returns(TwirpResponse)
      end
      def create_curated_image_definition(name:, os_type:, architecture:, enabled:, feature_flag:)
        rpc(
          :CreateCuratedImageDefinition,
          name: name,
          os_type: os_type,
          architecture: architecture,
          enabled: enabled,
          feature_flag: feature_flag
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          version: String,
          source_vhd_url: String,
          enabled: T::Boolean
        ).returns(TwirpResponse)
      end
      def create_curated_image_version(image_definition_id:, version:, source_vhd_url:, enabled:)
        rpc(
          :CreateCuratedImageVersion,
          image_definition_id: image_definition_id,
          version: version,
          source_vhd_url: source_vhd_url,
          enabled: enabled
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          name: String,
          enabled: T::Boolean,
          feature_flag: String
        ).returns(TwirpResponse)
      end
      def update_curated_image_definition(image_definition_id:, name:, enabled:, feature_flag:)
        rpc(
          :UpdateCuratedImageDefinition,
          image_definition_id: image_definition_id,
          name: name,
          enabled: enabled,
          feature_flag: feature_flag
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
          points_to_image_definition_id: Integer,
          enabled: T::Boolean,
          feature_flag: String
        ).returns(TwirpResponse)
      end
      def create_curated_image_definition_pointer(name:, points_to_image_definition_id:, enabled:, feature_flag:)
        rpc(
          :CreateCuratedImageDefinitionPointer,
          name: name,
          points_to_image_definition_id: points_to_image_definition_id,
          enabled: enabled,
          feature_flag: feature_flag
        )
      end

      sig do
        params(
          image_definition_id: Integer,
          name: String,
          points_to_image_definition_id: Integer,
          enabled: T::Boolean,
          feature_flag: String
        ).returns(TwirpResponse)
      end
      def update_curated_image_definition_pointer(image_definition_id:, name:, points_to_image_definition_id:, enabled:, feature_flag:)
        rpc(
          :UpdateCuratedImageDefinitionPointer,
          image_definition_id: image_definition_id,
          name: name,
          points_to_image_definition_id: points_to_image_definition_id,
          enabled: enabled,
          feature_flag: feature_flag
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
