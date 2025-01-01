# typed: false
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      # Handler for the MonolithTwirp::Registrymetadata::Core::V1::LoginAPIService
      class LoginAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w(packageregistry package_registry).freeze
        handles_service MonolithTwirp::Registrymetadata::Core::V1::LoginAPIService

        ERR_UNAUTHENTICATED = "User cannot be authenticated with the token provided."
        ERR_FORBIDDEN = "The token provided does not match expected scopes."
        ERR_INSTALLATION = "The requested installation does not exist."

        # validate_token_scopes doesn't need tenant context as it operates on owner ids
        exempt_from_tenant_context_requirement(only: %i[validate_token_scopes])

        def before_rpc(rack_env, env)
          ::Api::Internal::Twirp::Registrymetadata::Core::Access.call(service, self, rack_env, env)
        end

        # Public: Implementation of the ValidateTokenScopes Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Registrymetadata::Core::V1::ValidateTokenScopesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Registrymetadata::Core::V1::ValidateTokenScopesResponse, or a Twirp::Error.
        def validate_token_scopes(req, env)
          # Instantiate a new authorization class with its own ivars, for each request
          new_auth = Api::Internal::Twirp::Registrymetadata::Core::V1::Authorization.new(req, env)

          unless new_auth.login_successful?
            return Twirp::Error.unauthenticated(ERR_UNAUTHENTICATED, {})
          end

          if !new_auth.installation && !new_auth.expected_scopes_match?
            return Twirp::Error.permission_denied(ERR_FORBIDDEN, {})
          end

          # If there is no owner (`ownerID: 0`) we're dealing with the special case when this route is called for CLI login only (not for package operations).
          unless new_auth.current_owner
            return serialized_login(new_auth)
          end

          is_site_scoped_installation = new_auth.installation.is_a?(SiteScopedIntegrationInstallation)
          allow_access_package_not_owned_by_target = is_site_scoped_installation && Apps::Internal.capable?(:access_package_not_owned_by_target, app: new_auth.installation.integration)
          # Deny request if the owner of the installation does not match the org sent in the request
          # Skip this check for codespaces tokens because it's legitimate for a codespace to be owned by a user
          # while the "current_owner" is the org the package they're acting against belongs to
          if new_auth.current_owner && new_auth.installation && !allow_access_package_not_owned_by_target
            # Skip this check for requests to read an internal package, we defer authorization for this special case to authzd
            # For public packages as well read can happen from another org, so skip this check
            unless req.package_visibility.in?([:PACKAGE_VISIBILITY_INTERNAL, :PACKAGE_VISIBILITY_PUBLIC]) && new_auth.package_read?
              if new_auth.installation.target_id != new_auth.current_owner.id
                return Twirp::Error.permission_denied(ERR_INSTALLATION, {})
              end
            end
          end

          # Call Rails authorization middleware
          begin
            unless new_auth.auth_middleware_validated?
              return Twirp::Error.permission_denied(ERR_FORBIDDEN, {})
            end
          rescue Platform::Errors::Forbidden => e
            return Twirp::Error.permission_denied(e.to_s, {})
          rescue Platform::Errors::NotFound => e
            return Twirp::Error.not_found(e.to_s, {})
          end

          serialized_login(new_auth)
        end

        private

        def serialized_login(new_auth)
          installation = new_auth.installation
          integration = installation.try(:integration)

          is_site_scoped_installation = installation.is_a?(SiteScopedIntegrationInstallation)
          allow_access_package_not_owned_by_target = is_site_scoped_installation && Apps::Internal.capable?(:access_package_not_owned_by_target, app: integration)

          logged_in_user = new_auth.current_user
          repo = new_auth.current_repo
          ownertype = repo.owner.type if repo
          # This branching based on whether or not to set an owner_type, is a weird and known issue
          # which was introduced after attempting to fix a packages bug in Actions, see: https://github.com/github/registry-metadata/pull/922
          # It is likely that it does not matter whether we pass in an owner_type for Codespaces because
          # the owner_type is solely used when creating a new package using a (Site-)Scoped Installation login
          # to determine whether the package should be created in the user's namespace or the org's namespace.
          # The issue to fix, and hopefully unify this logic is: https://github.com/github/package-registry-team/issues/7420
          if allow_access_package_not_owned_by_target
            {
              site_scoped_installation_login: serialize_site_scoped_installation_login(new_auth,
                owner_type: "", # Codespaces hasn't needed to set owner_type so just pass along a blank string
                integration_name: Apps::Internal.property(:packages_authorization_name, app: integration))
            }
          elsif is_site_scoped_installation # Actions Global App SSII
            {
              site_scoped_installation_login: serialize_site_scoped_installation_login(new_auth,
                owner_type: ownertype,
                integration_name: Apps::Internal.property(:packages_authorization_name, app: integration))
            }
          elsif installation # Actions non-Global App SII
            {
              installation_login: serialize_installation_login(new_auth)
            }
          else
            {
              oauth_login: {
                user_id: logged_in_user.id,
                user_name: logged_in_user.login,
                scopes: logged_in_user.scopes
              }
            }
          end
        end

        def serialize_installation_login(new_auth)
          installation = new_auth.installation
          repo = new_auth.current_repo
          ownertype = repo.owner.type if repo
          all_repositories = new_auth.repositories&.includes(:internal_repository)
          repo_id = repo.id if repo
          repo_vis = repo ? repo_visibility(repo) : :PACKAGE_VISIBILITY_PRIVATE
          {
            installation_id: installation.id,
            permissions: installation.permissions,
            parent_installation_id: defined?(installation.integration_installation_id) ? installation.integration_installation_id : nil,
            integration_id: installation.integration_id,
            repo_id: repo_id,
            repo_visibility: repo_vis,
            repositories: all_repositories.map(&method(:serialize_repo)),
            owner_type: ownertype,
            user_name: installation.bot.display_login
          }
        end

        def serialize_site_scoped_installation_login(new_auth, owner_type:, integration_name:)
          logged_in_user = new_auth.current_user
          installation = new_auth.installation
          repo = new_auth.current_repo

          {
            user_id: logged_in_user.id,
            user_name: logged_in_user.login,

            installation_id: installation.id,
            permissions: installation.permissions,
            integration_id: installation.integration_id,
            repositories: [repo].compact.map(&method(:serialize_repo)),
            owner_type: owner_type,
            integration_name: integration_name
          }
        end

        def repo_visibility(repo)
          return :PACKAGE_VISIBILITY_PUBLIC if repo.public?
          return :PACKAGE_VISIBILITY_INTERNAL if repo.internal?
          :PACKAGE_VISIBILITY_PRIVATE
        end

        def serialize_repo(repo)
          {
            id: repo.id,
            name: repo.name,
            visibility: repo_visibility(repo)
          }
        end

      end
    end
  end
end
