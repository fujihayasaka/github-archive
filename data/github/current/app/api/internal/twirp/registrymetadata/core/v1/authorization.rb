# typed: true
# frozen_string_literal: true

require "monolith-twirp-registrymetadata-core"

module Api::Internal::Twirp::Registrymetadata
  module Core
    module V1
      class Authorization
        include Platform::Authorization
        include App::IExecContextAccessor

        READ_OPERATION_SCOPES = ["read:packages"]

        attr_reader :current_user, :current_owner, :installation, :oauth, :response

        def initialize(req, env)
          token = env[:authorization].sub(/\A(Bearer|bearer|Token|token) /, "")

          # This stubs all of the instance variables needed to get through the
          # the Rails authorization code.
          #
          # Cause we expect it to be coming from Sinatra.
          @remote_ip = env[:real_ip]
          @response  = Sinatra::Response.new
          @request   = req
          @installation = nil

          # Setting this instance variable overrides the one set
          # in the method `api_auth`.
          @api_auth = GitHub::Authentication::Attempt.new(
              allow_integrations:                 true,
              allow_user_via_granular_actor:         true,
              from:                               :internal_api,
              token:                              token,
              ip:                                 remote_ip,
              user_agent:                         env[:user_agent],
              request_id:                         env[:request_id],
              password_auth_blocked:              true,
              url:                                env[:path],
              )

          @result = @api_auth.result

          if login_successful?
            @current_owner = User.find_by(id: owner_id) if owner_id && owner_id > 0
            @current_org = @current_owner if @current_owner && @current_owner.organization?
            @current_user = @result.user
            @oauth = @current_user.oauth_access
            if @current_user.is_a?(Bot)
              @installation = @current_user.installation
              if @installation.nil?
                GitHub.logger.info(
                  "Could not find installation for bot user",
                  "code.namespace" => self.class.name,
                  "code.function" => __method__,
                )
              end
            else
              if @oauth.try(:installation).is_a?(SiteScopedIntegrationInstallation)
                @installation = @oauth.installation
              end
            end
          end
        end

        sig { override.returns(App::IContext) }
        def exec_context
          App::SimpleContext.new
        end

        def login_successful?
          @result.success?
        end

        def expected_scopes_match?
          @request.expected_scopes.all? { |scope| Api::AccessControl.scope?(@current_user, scope) }
        end

        def auth_middleware_validated?
          # Create a placeholder package because access_allowed? wants an obj for resource
          pkg = ::PackageRegistry::Package.new(PackageWrapper.new(id: nil)).tap do |p|
            p.owner_id = owner_id
            p.repo_id = current_repo&.id
          end

          access_allowed?(:authenticate_for_registry, resource: pkg, organization: @current_org, allow_integrations: true, allow_user_via_granular_actor: true)
        end

        # These override methods in `Authorization` to short-circuit (or implement) data requirements.
        #
        # Actually, not all of them are overrides: some are just implicitly
        # required by the methods in `Authorization`.
        def current_resource_org_or_biz_owner
          current_owner if @current_owner.organization?
        end

        alias :find_org :current_resource_org_or_biz_owner

        def current_repo_loaded?
          current_repo.present?
        end

        def repositories
          return @repositories if defined?(@repositories)
          @repositories = @installation.repositories if installation&.repositories
        end

        def current_repo
          return @current_repo if defined?(@current_repo)
          # If this is a scoped installation is associated with more than one repo, do not associate it with any
          return @current_repo = @installation.repositories.first if @installation&.repositories&.length == 1

          # If it is a site scoped installation then the current_repo should always be the origin repository
          if @installation&.repositories && @installation&.repositories.length > 1 && @installation.is_a?(SiteScopedIntegrationInstallation)
            @current_repo = Codespace.find_by(id: @installation.codespace_ids&.first)&.repository
          end
        end

        alias :find_repo :current_repo

        def graphql_request?
          true
        end

        def repo_nwo_from_path
          current_repo_loaded? && @current_repo.nwo
        end

        def remote_ip
          @remote_ip
        end

        def real_ip
          @remote_ip
        end

        def owner_id
          return @owner_id if defined?(@owner_id)
          @owner_id = request.owner_id
        end

        def request
          @request
        end

        # returns true if the operation was a read request, false otherwise.
        # used by the ConditionalAccess::Enforcer
        def read_request?
          return true if package_login?
          return true if package_read?
          false
        end

        def package_login?
          owner_id == 0
        end

        def package_read?
          request.expected_scopes == READ_OPERATION_SCOPES
        end

        def params
          {}
        end
      end
    end
  end
end
