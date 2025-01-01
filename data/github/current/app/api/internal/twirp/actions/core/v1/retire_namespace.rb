# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class RetireNamespace
        attr_reader :req, :env

        def self.call(req, env)
          ActiveRecord::Base.connected_to(role: :writing) do
            new(req, env).call
          end
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          owner_and_name = req.nwo.split("/")
          if owner_and_name.length != 2
            return Twirp::Error.invalid_argument("must be a legal nwo", argument: "nwo")
          end

          if GitHub.multi_tenant_enterprise?
            current_tenant = GitHub::CurrentTenant.get
            unless current_tenant.present?
              return Twirp::Error.invalid_argument("failed to get current tenant")
            end

            owner_login = owner_and_name[0] + "_" + current_tenant.shortcode
          else
            owner_login = owner_and_name[0]
          end

          name = owner_and_name[1]

          unless RetiredNamespace.retire(owner: owner_login, name: name).success?
            return Twirp::Error.internal("failed to retire namespace")
          end

          {}
        end
      end
    end
  end
end
