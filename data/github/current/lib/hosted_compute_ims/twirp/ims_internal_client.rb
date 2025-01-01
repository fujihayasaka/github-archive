# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class InternalClient < HostedComputeIms::Twirp::BaseClient
      OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }
      def initialize
        super(base_url: GitHub.hosted_compute_ims_url_curated)
      end

      sig do
        params(
          id: Integer,
          source: String,
          version: String,
          owner: OrgOrEnterprise
        ).returns(TwirpResponse)
      end
      def get_image_details(id:, source:, version:, owner:)
        rpc(
          :GetImageDetails,
          image_key: build_image_key(id: id, source: source, version: version),
          owner: build_actor(owner: owner),
        )
      end

      sig do
        params(
          id: Integer,
          source: String,
          version: String,
        ).returns(TwirpResponse)
      end
      def get_image_reference(id:, source:, version:)
        rpc(
          :GetImageReference,
          image_key: build_image_key(id: id, source: source, version: version)
        )
      end

      sig { returns(T.class_of(GitHub::HostedComputeIms::InternalApi::InternalImageManagementServiceClient)) }
      def twirp_class
        GitHub::HostedComputeIms::InternalApi::InternalImageManagementServiceClient
      end
    end

  end
end
