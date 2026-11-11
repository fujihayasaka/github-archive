# typed: true
# frozen_string_literal: true

require "monolith-twirp-mcpregistry-identity"

module Api::Internal::Twirp::Mcpregistry
  module Identity
    module V1
      # Handler for the MonolithTwirp::Mcpregistry::Identity::V1::IdentityAPIService
      class IdentityAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["mcp_registry"]
        handles_service MonolithTwirp::Mcpregistry::Identity::V1::IdentityAPIService

        sig do
          override.params(
            rack_env: T::Hash[T.untyped, T.untyped],
            env: T::Hash[T.untyped, T.untyped]
          ).void
        end
        def before_rpc(rack_env, env)
          super
          env[:user_token] = rack_env["HTTP_USER_TOKEN"].to_s
        end

        # Public: Implementation of the GetUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Identity::V1::GetUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Mcpregistry::Identity::V1::GetUserResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Mcpregistry::Identity::V1::GetUserRequest,
            env: T::Hash[T.untyped, T.untyped]
          ).returns(T.any(MonolithTwirp::Mcpregistry::Identity::V1::GetUserResponse, Twirp::Error))
        end
        def get_user(req, env)
          token_header = T.cast(env[:user_token], String)
          token = token_header.to_s.strip.split(/\s+/).last.to_s

          return Twirp::Error.unauthenticated("user token missing") if token.blank?

          user = resolve_user_from_token(token)

          return Twirp::Error.unauthenticated("user token invalid") unless user

          MonolithTwirp::Mcpregistry::Identity::V1::GetUserResponse.new(user_id: user.id, login: user.login)
        end

        # Public: Implementation of the GetMemberships Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Identity::V1::GetMembershipsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Mcpregistry::Identity::V1::GetMembershipsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Mcpregistry::Identity::V1::GetMembershipsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Mcpregistry::Identity::V1::GetMembershipsResponse, Twirp::Error))
        end
        def get_memberships(req, env)
          user_id = req.user_id
          return Twirp::Error.invalid_argument("user_id must be > 0") if user_id <= 0

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user not found") unless user

          membership_klass = MonolithTwirp::Mcpregistry::Identity::V1::Membership
          org_type = MonolithTwirp::Mcpregistry::Identity::V1::Membership::Type::TYPE_ORG
          ent_type = MonolithTwirp::Mcpregistry::Identity::V1::Membership::Type::TYPE_ENTERPRISE
          admin_role = MonolithTwirp::Mcpregistry::Identity::V1::Membership::Role::ROLE_ADMIN
          member_role = MonolithTwirp::Mcpregistry::Identity::V1::Membership::Role::ROLE_MEMBER

          memberships = T.let([], T::Array[MonolithTwirp::Mcpregistry::Identity::V1::Membership])
          enterprises = T.let([], T::Array[T.untyped])

          organizations = user.organizations.to_a
          ActiveRecord::Associations::Preloader.new(records: organizations, associations: :business).call

          organizations.each do |org|

            memberships << membership_klass.new(
              type: org_type,
              id: org.id,
              role: org.adminable_by?(user) ? admin_role : member_role
            )

            ent = enterprise_for_org(org)
            enterprises << ent if ent
          end

          user.businesses.each do |business|
            enterprises << business
          end

          enterprises.compact!
          enterprises.uniq! { |e| e.id }

          enterprises.each do |enterprise|
            memberships << membership_klass.new(
              type: ent_type,
              id: enterprise.id,
              role: enterprise_admin?(enterprise, user) ? admin_role : member_role
            )
          end

          # Dedupe by (type, id), put prefer ADMIN if we somehow got both.
          # Sorting by role asc keeps admin first.
          memberships.sort_by! { |m| [m.type, m.id, m.role] }
          memberships.uniq! { |m| [m.type, m.id] }
          memberships.sort_by! { |m| [m.type, m.id] }

          MonolithTwirp::Mcpregistry::Identity::V1::GetMembershipsResponse.new(memberships: memberships)
        end

        # Public: Implementation of the GetCopilotAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Identity::V1::GetCopilotAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Mcpregistry::Identity::V1::GetCopilotAccessResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Mcpregistry::Identity::V1::GetCopilotAccessRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Mcpregistry::Identity::V1::GetCopilotAccessResponse, Twirp::Error))
        end
        def get_copilot_access(req, env)

          user_id = req.user_id
          return Twirp::Error.invalid_argument("user_id must be > 0") if user_id <= 0

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("user not found") unless user

          copilot_user = Copilot::User.new(user)

          org_ids =
            if copilot_user.has_cfb_access? || copilot_user.has_cfe_access?
              copilot_user.orgs_using_copilot_for_business.map(&:id).uniq
            else
              []
            end

          MonolithTwirp::Mcpregistry::Identity::V1::GetCopilotAccessResponse.new(
            has_cfb_access: copilot_user.has_cfb_access?,
            has_cfe_access: copilot_user.has_cfe_access?,
            has_cfi_access: copilot_user.has_cfi_access?,
            has_free_access: copilot_user.has_free_access?,
            has_limited_access: copilot_user.has_limited_access?,
            copilot_organization_ids: org_ids,
          )
        end

        # Public: Implementation of the GetOrgEnterprise Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Identity::V1::GetOrgEnterpriseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Mcpregistry::Identity::V1::GetOrgEnterpriseResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Mcpregistry::Identity::V1::GetOrgEnterpriseRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Mcpregistry::Identity::V1::GetOrgEnterpriseResponse, Twirp::Error))
        end
        def get_org_enterprise(req, env)
          org_id = req.org_id
          return Twirp::Error.invalid_argument("org_id must be > 0") if org_id <= 0

          org = Organization.includes(:business).find_by(id: org_id)
          return Twirp::Error.not_found("org not found") unless org

          enterprise = enterprise_for_org(org)

          MonolithTwirp::Mcpregistry::Identity::V1::GetOrgEnterpriseResponse.new(
            enterprise_id: enterprise&.id || 0,
          )
        end

        # Public: Implementation of the ResolveNamespace Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Mcpregistry::Identity::V1::ResolveNamespaceRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Mcpregistry::Identity::V1::ResolveNamespaceResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Mcpregistry::Identity::V1::ResolveNamespaceRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Mcpregistry::Identity::V1::ResolveNamespaceResponse, Twirp::Error))
        end
        def resolve_namespace(req, env)
          namespace = req.namespace.to_s.strip.downcase
          return Twirp::Error.invalid_argument("namespace must be present") if namespace.blank?

          principal = User.find_by_login(namespace)
          return Twirp::Error.not_found("namespace not found") unless principal

          type = if principal.is_a?(Organization)
            MonolithTwirp::Mcpregistry::Identity::V1::ResolveNamespaceResponse::Type::TYPE_ORG
          else
            MonolithTwirp::Mcpregistry::Identity::V1::ResolveNamespaceResponse::Type::TYPE_USER
          end

          MonolithTwirp::Mcpregistry::Identity::V1::ResolveNamespaceResponse.new(
            type: type,
            id: principal.id,
          )
        end

        private

        # Resolves a User from a signed auth token scoped to the MCP Registry.
        sig { params(token: String).returns(T.nilable(User)) }
        def resolve_user_from_token(token)
          sat = GitHub::Authentication::SignedAuthToken.verify(
            token: token,
            scope: "mcp_registry",
          )
          sat&.user if sat&.valid?
        rescue StandardError => e
          Rails.logger.warn("[MCP Identity] Unexpected error resolving token: #{e.class}: #{e.message}")
          nil
        end

        sig { params(org: T.untyped).returns(T.untyped) }
        def enterprise_for_org(org)
          return T.unsafe(org).business if org.respond_to?(:business)
          return T.unsafe(org).enterprise if org.respond_to?(:enterprise)
          nil
        end

        sig { params(enterprise: T.untyped, user: T.untyped).returns(T::Boolean) }
        def enterprise_admin?(enterprise, user)
          return T.unsafe(enterprise).adminable_by?(user) if enterprise.respond_to?(:adminable_by?)
          return T.unsafe(enterprise).owner?(user) if enterprise.respond_to?(:owner?)
          false
        end
      end
    end
  end
end
