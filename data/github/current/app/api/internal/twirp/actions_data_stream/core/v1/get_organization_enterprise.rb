# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::ActionsDataStream
  module Core
    module V1
      class GetOrganizationEnterprise
        attr_reader :req, :env

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          organization_id = req.organization_id
          if organization_id.nil? || organization_id == 0
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          unless organization = Organization.find_by(id: organization_id)
            return Twirp::Error.not_found("organization does not exist", argument: "organization_id")
          end

          { enterprise_id: organization.business&.id || 0 }
        end
      end
    end
  end
end
