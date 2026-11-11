# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class CustomerImagesClient < HostedComputeIms::Twirp::BaseClient
      sig do
        params(
          owner: OrgOrEnterprise,
          runner_group_id: T.nilable(Integer)
        ).returns(TwirpResponse)
      end
      def list_customer_image_definitions(owner:, runner_group_id: nil)
        rpc(
          :ListCustomerImageDefinitions,
          owner: build_actor(owner: owner),
          runner_group_id: runner_group_id
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
          os_type: T.nilable(Symbol),
          architecture: T.nilable(Symbol)
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
          source_vhd_url: String,
          vm_generation: T.nilable(Symbol),
          os_state: T.nilable(Symbol)
        ).returns(TwirpResponse)
      end
      def create_customer_image_version(owner:, image_definition_id:, version:, source_vhd_url:, vm_generation: nil, os_state: nil)
        rpc(
          :CreateCustomerImageVersion,
          owner: build_actor(owner: owner),
          image_definition_id: image_definition_id,
          version: version,
          source_vhd_url: source_vhd_url,
          vm_generation: vm_generation,
          os_state: os_state
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
