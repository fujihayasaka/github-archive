# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class CuratedImagesClient < HostedComputeIms::Twirp::BaseClient
      extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

      OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }

      def initialize
        super(base_url: GitHub.hosted_compute_ims_url_curated)
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          include_disabled: T::Boolean
        ).returns(TwirpResponse)
      end
      def list_curated_image_definitions(owner:, include_disabled:)
        rpc(
          :ListCuratedImageDefinitions,
          owner: build_actor(owner: owner),
          include_disabled: include_disabled
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer
        ).returns(TwirpResponse)
      end
      def get_curated_image_definition(owner:, image_definition_id:)
        rpc(
          :GetCuratedImageDefinition,
          image_definition_id: image_definition_id,
          owner: build_actor(owner: owner)
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer,

        ).returns(TwirpResponse)
      end
      def list_curated_image_versions(owner:, image_definition_id:)
        rpc(
          :ListCuratedImageVersions,
          image_definition_id: image_definition_id,
          owner: build_actor(owner: owner)
        )
      end

      sig do
        params(
          owner: OrgOrEnterprise,
          image_definition_id: Integer,
          version: String
        ).returns(TwirpResponse)
      end
      def get_curated_image_version(owner:, image_definition_id:, version:)
        rpc(
          :GetCuratedImageVersion,
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
