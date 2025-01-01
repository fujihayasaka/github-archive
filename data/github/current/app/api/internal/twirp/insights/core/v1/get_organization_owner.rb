# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Insights
  module Core
    module V1
      class GetOrganizationOwner
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
          org_id = req.id
          if org_id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "id")
          end

          unless org = Organization.find_by(id: org_id)
            return Twirp::Error.not_found("organization does not exist", argument: "id")
          end

          {}.tap do |res|
            res[:organization] = build_actor(org)
            res[:organization_plan_name] = (org.business || org).plan.name
            res[:business] = build_actor(org.business) if org.business
          end
        end
      end
    end
  end
end
