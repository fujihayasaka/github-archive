# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    class SbomClient < DependencyGraphPlatform::Twirp::BaseClient
      DEFAULT_READ_TIMEOUT = 10.seconds
      DEFAULT_SIGNED_LINK_TTL_MINUTES = 5
      MAX_SIGNED_LINK_TTL_MINUTES = 60

      sig { params(repository_id: Integer).returns(Github::DependencyGraphPlatform::Sbom::V1::GetSBOMResponse) }
      def get_sbom(repository_id:)
        rpc_request = {
          repository_id: repository_id,
        }
        rpc(:GetSBOM, rpc_request)
      end

      sig { params(repository_id: Integer).returns(Github::DependencyGraphPlatform::Sbom::V1::CreateSBOMResponse) }
      def create_sbom(repository_id:)
        rpc_request = {
          repository_id: repository_id,
        }
        rpc(:CreateSBOM, rpc_request)
      end

      sig { params(sbom_uuid: String, repository_id: Integer, signed_link_ttl_minutes: Integer).returns(Github::DependencyGraphPlatform::Sbom::V1::GetSBOMResultResponse) }
      def get_sbom_result(sbom_uuid:, repository_id:, signed_link_ttl_minutes: DEFAULT_SIGNED_LINK_TTL_MINUTES)
        if signed_link_ttl_minutes > MAX_SIGNED_LINK_TTL_MINUTES
          raise ArgumentError, "signed_link_ttl_minutes must not exceed #{MAX_SIGNED_LINK_TTL_MINUTES}, got #{signed_link_ttl_minutes}"
        end

        if signed_link_ttl_minutes <= 0
          raise ArgumentError, "signed_link_ttl_minutes must not be zero or negative, got #{signed_link_ttl_minutes}"
        end

        rpc_request = {
          sbom_uuid: sbom_uuid,
          repository_id: repository_id,
          signed_link_ttl_minutes: signed_link_ttl_minutes,
        }
        rpc(:GetSBOMResult, rpc_request)
      end

      sig { params(sbom_uuid: String, repository_id: Integer).returns(Github::DependencyGraphPlatform::Sbom::V1::PollSBOMResultResponse) }
      def poll_sbom_result(sbom_uuid:, repository_id:)
        rpc_request = {
          sbom_uuid: sbom_uuid,
          repository_id: repository_id,
        }
        rpc(:PollSBOMResult, rpc_request)
      end

      private

      def client_name
        "sbom"
      end

      def twirp_class
        Github::DependencyGraphPlatform::Sbom::V1::SBOMClient
      end
    end
  end
end
