# typed: true
# frozen_string_literal: true

require "monolith-twirp-actionsdatastream-core"

module Api::Internal::Twirp::ActionsDataStream
  module Core
    module V1
      class OrganizationEnterpriseAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["actions_data_stream"].freeze
        handles_service MonolithTwirp::ActionsDataStream::Core::V1::OrganizationEnterpriseAPIService

        resolve_tenant_context only: %i[get_organization_enterprise] do |req, _env|
          request = T.must(req)

          if request.organization_id.nil? || request.organization_id == 0
            next Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          Organization.find_by(id: request.organization_id)&.resolve_tenant
        end

        def get_organization_enterprise(req, env)
          GetOrganizationEnterprise.call(req, env)
        end
      end
    end
  end
end
