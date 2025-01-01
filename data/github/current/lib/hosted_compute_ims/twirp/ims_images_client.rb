# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class ImagesClient < HostedComputeIms::Twirp::BaseClient
      extend T::Sig

      OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }

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
          owner: OrgOrEnterprise
        ).returns(TwirpResponse)
      end
      def list_customer_image_definitions(owner:)
        rpc(
          :ListCustomerImageDefinitions,
          owner_id: owner.next_global_id
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer
        ).returns(TwirpResponse)
      end
      def get_customer_image_definition(owner:, image_definition_id:)
        rpc(
          :GetCustomerImageDefinition,
          owner_id: owner.next_global_id,
          image_definition_id: image_definition_id
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer
        ).returns(TwirpResponse)
      end
      def list_customer_image_versions(owner:, image_definition_id:)
        rpc(
          :ListCustomerImageVersions,
          owner_id: owner.next_global_id,
          image_definition_id: image_definition_id
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer,
          version: String
        ).returns(TwirpResponse)
      end
      def get_customer_image_version(owner:, image_definition_id:, version:)
        rpc(
          :GetCustomerImageVersion,
          owner_id: owner.next_global_id,
          image_definition_id: image_definition_id,
          version: version
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          name: String,
          os_type: Integer,
          architecture: Integer
        ).returns(TwirpResponse)
      end
      def create_customer_image_definition(owner:, name:, os_type:, architecture:)
        rpc(
          :CreateCustomerImageDefinition,
          owner_id: owner.next_global_id,
          name: name,
          os_type: os_type,
          architecture: architecture
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer,
          version: String,
          source_vhd_url: String
        ).returns(TwirpResponse)
      end
      def create_customer_image_version(owner:, image_definition_id:, version:, source_vhd_url:)
        rpc(
          :CreateCustomerImageVersion,
          owner_id: owner.next_global_id,
          image_definition_id: image_definition_id,
          version: version,
          source_vhd_url: source_vhd_url
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer,
          name: String
        ).returns(TwirpResponse)
      end
      def update_customer_image_definition(owner:, image_definition_id:, name:)
        rpc(
          :UpdateCustomerImageDefinition,
          owner_id: owner.next_global_id,
          image_definition_id: image_definition_id,
          name: name
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer,
        ).returns(TwirpResponse)
      end
      def delete_customer_image_definition(owner:, image_definition_id:)
        rpc(
          :DeleteCustomerImageDefinition,
          owner_id: owner.next_global_id,
          image_definition_id: image_definition_id,
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer,
          version: String
        ).returns(TwirpResponse)
      end
      def delete_customer_image_version(owner:, image_definition_id:, version:)
        rpc(
          :DeleteCustomerImageVersion,
          owner_id: owner.next_global_id,
          image_definition_id: image_definition_id,
          version: version
        )
      end

      sig { returns(T.class_of(GitHub::HostedComputeIms::ImagesApi::ImageManagementServiceClient)) }
      def twirp_class
        GitHub::HostedComputeIms::ImagesApi::ImageManagementServiceClient
      end
    end
  end
end
