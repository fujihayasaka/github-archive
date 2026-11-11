# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module HostedComputeIms
  module Twirp
    class InternalClient < HostedComputeIms::Twirp::BaseClient
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
          image_id: id,
          image_source: source,
          image_version: version,
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
          image_id: id,
          image_source: source,
          image_version: version,
        )
      end

      sig { returns(T.class_of(GitHub::HostedComputeIms::InternalApi::InternalImageManagementServiceClient)) }
      def twirp_class
        GitHub::HostedComputeIms::InternalApi::InternalImageManagementServiceClient
      end
    end

  end
end
