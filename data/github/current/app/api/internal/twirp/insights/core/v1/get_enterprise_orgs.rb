# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Insights
  module Core
    module V1
      class GetEnterpriseOrgs
        include Api::Internal::Twirp::Insights::Core::V1::ActorsDependency

        attr_reader :req, :env

        def self.call(req, env)
          ActiveRecord::Base.connected_to(role: :reading) do
            new(req, env).call
          end
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          enterprise_id = req.id
          if enterprise_id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "id")
          end

          unless enterprise = Business.find_by(id: enterprise_id)
            return Twirp::Error.not_found("enterprise does not exist", argument: "id")
          end

          {
            enterprise: build_actor(enterprise),
            organizations:  enterprise.organizations.map { |org| build_actor(org) }
          }
        end
      end
    end
  end
end
