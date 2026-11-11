# typed: true
# frozen_string_literal: true

require "monolith-twirp-code_scanning-enterprise"

module Api::Internal::Twirp::CodeScanning
  module Enterprise
    module V1
      class StorageAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["turboscan"]
        handles_service MonolithTwirp::CodeScanning::Enterprise::V1::StorageAPIService
        exempt_from_tenant_context_requirement(only: %i[hosts])

        sig do
          params(
            req: MonolithTwirp::CodeScanning::Enterprise::V1::HostsRequest,
            env: T::Hash[String, T.untyped],
          ).returns(T.any(MonolithTwirp::CodeScanning::Enterprise::V1::HostsResponse, Twirp::Error))
        end
        def hosts(req, env)
          return Twirp::Error.unimplemented("not implemented") unless GitHub.enterprise?

          MonolithTwirp::CodeScanning::Enterprise::V1::HostsResponse.new(
            least_loaded: GitHub::Storage::Allocator.least_loaded_hosts,
          )
        end
      end
    end
  end
end
