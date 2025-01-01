# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class CustomerImagesClient < HostedComputeIms::Twirp::BaseClient
      extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

      OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }

      def initialize
        super(base_url: GitHub.hosted_compute_ims_url_customer)
      end

      sig do
        params(
          owner: OrgOrEnterprise
        ).returns(TwirpResponse)
      end
      def list_customer_image_definitions(owner:)
        rpc(
          :ListCustomerImageDefinitions,
          owner: build_actor(owner: owner)
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
          owner: build_actor(owner: owner),
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
          owner: build_actor(owner: owner),
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
          owner: build_actor(owner: owner),
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
          owner: build_actor(owner: owner),
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
          owner: build_actor(owner: owner),
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
          owner: build_actor(owner: owner),
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
          owner: build_actor(owner: owner),
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
          owner: build_actor(owner: owner),
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
