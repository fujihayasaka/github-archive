# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    class SbomClient < DependencyGraphPlatform::Twirp::BaseClient
      DEFAULT_READ_TIMEOUT = GitHub.default_request_timeout

      sig { params(repository_id: Integer).returns(Github::DependencyGraphPlatform::Sbom::V1::GetSBOMResponse) }
      def get_sbom(repository_id:)
        rpc_request = {
          repository_id: repository_id,
        }
        rpc(:GetSBOM, rpc_request)
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
