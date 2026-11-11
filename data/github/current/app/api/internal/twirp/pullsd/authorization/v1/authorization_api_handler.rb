# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-authorization"

module Api::Internal::Twirp::Pullsd
  module Authorization
    module V1

      # Handler for the MonolithTwirp::Pullsd::Authorization::V1::AuthorizationAPIService
      class AuthorizationAPIHandler < Api::Internal::Twirp::Handler
        class Authorizer
          extend T::Helpers

          HaltError = Class.new(StandardError)

          # public API
          attr_reader :status, :message, :documentation_url, :errors

          include Platform::Authorization
          include App::IExecContextAccessor
          include Api::App::UserLoginDependency
          include Api::App::UserLoginDependency::IUserLoginDependency
          include Platform::Authorization::RestApiFailedLoginHelper

          # To avoid sweeping changes to Api::App::ErrorDependency due to Sorbet
          # limitations with how `requires_ancestor` and interfaces interop, so
          # I decided to include the module directly outside of the type system.
          #
          # Test coverage should be ensuring this works as expected.
          send(:include, Api::App::ErrorDependency)

          # RequestWrapper wraps the Twirp request to add an `env` accessor
          # so that we can mimic a Sinatra request object.
          class RequestWrapper < SimpleDelegator
            attr_accessor :env

            def url
              ""
            end
          end

          class MockResponse
            def headers
              @_headers ||= {}
            end
          end

          attr_reader :request, :env

          def initialize(
            repo:,
            request:,
            read_request:,
            remote_ip:,
            # token is an IET
            token:
          )
            @repo = repo
            @request = RequestWrapper.new(request)
            # fetch from Twirp request headers once we're passing them through
            @request.env = @env = {
              "HTTP_X_GITHUB_REQUEST_ID": nil
            }
            @token = token

            @read_request = read_request
            @remote_ip = remote_ip
          end

          # rubocop:disable GitHub/ApiMethodsCallingDeliverBangMustHaveBangs
          def access_allowed?(*args)
            super.tap do |result|
              unless result
                deliver_authorization_error!
              end
            end
          rescue HaltError
            false
          end

          sig { override.returns(App::IContext) }
          def exec_context
            @_context ||= App::SimpleContext.new.tap do |context|
              context.actor = @actor
              context.organization = @repo.organization if @repo
              context.repository = @repo
              context.business = @repo.business if @repo
            end
          end

          def read_request?
            @read_request
          end

          def repo_nwo_from_path
            @repo.nwo
          end

          # GraphQL raises, which isn't ideal. We set this to `false` so the
          # deliver_* family of methods are called and we can capture the error
          # message, status code, etc.
          def graphql_request?
            false
          end

          def current_resource_org_or_biz_owner
            @repo.owner if @repo.owner&.organization?
          end

          def current_repo_loaded?
            @repo.present?
          end

          def current_repo
            @repo
          end

          def find_repo
            current_repo
          end

          # TODO this is definitely not right, and something pullsd will likely need to pass
          def request_access_security_header
            nil
          end

          def remote_ip
            @remote_ip
          end

          def response
            @response ||= MockResponse.new
          end

          # Override UserLoginDependency#request_credentials to bypass logic
          # that reaches into (missing in our case) rack.env
          def request_credentials
            Api::RequestCredentials.new.tap do |creds|
              creds.internal_exchange_token = @token if @token.present?
            end
          end

          def deliver_error(status, options = {})
            data = T.unsafe(self).deliver_error_data(status, options)
            @status = status
            @message = data[:message]
            @documentation_url = data[:documentation_url]
            @errors = data[:errors]
          end

          def log_data
            raise "`log_data` Not implemented"
          end

          def password_auth_blocked?
            !GitHub.api_password_auth_supported?
          end

          def source
            :api_other
          end

          UTC = ActiveSupport::TimeZone["UTC"]

          # Get the timezone based on current request and user context
          def timezone_for_request(user)
            zone = ActiveSupport::TimeZone[timezone_name]
            zone ||= user.time_zone if user
            zone || UTC
          end

          # TODO: Update timezone to be passed from the Twirp API
          def timezone_name
            # TODO: must pass this from the Twirp API
            if header = request.env["HTTP_TIME_ZONE"] || request.env["HTTP_X_TIME_ZONE"] ||
                        request.env["HTTP_TIMEZONE"]
              name = header.split(";").last if header =~ /[[:print:]]+/
            end
            name.to_s
          end

          def halt(*args)
            raise HaltError.new
          end

          def user_agent
            @user_agent ||= Api::UserAgent.new("pullsd/twirp")
          end

          # The following methods are required by Platform::Authorization but are not used in this context.
          # They raise "Not Implemented" since they _shouldn't_ be called.

          def medias
            raise "`medias` Not implemented"
          end

          def find_org
            current_resource_org_or_biz_owner
          end

          def deliver_error!(status, options = {})
            deliver_error(status, options)
          end

          def params
            raise "`params` Not implemented"
          end
        end

        allow_access_for :client, allowed_clients: ["pullsd"]
        handles_service MonolithTwirp::Pullsd::Authorization::V1::AuthorizationAPIService

        attr_reader :response, :request

        # Public: Implementation of the AuthorizeGetPullRequest Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Authorization::V1::AuthorizeGetPullRequestRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Authorization::V1::AuthorizeGetPullRequestResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Authorization::V1::AuthorizeGetPullRequestRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Authorization::V1::AuthorizeGetPullRequestResponse, Twirp::Error))
        end
        def authorize_get_pull_request(req, env)
          if unsupported_environment?
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeGetPullRequestResponse.new(
              authorized: false,
              message: "Not Found",
              status_code: 404,
            )
          end

          if req.repository_id == 0 || req.pull_request_id == 0
            return Twirp::Error.new(:invalid_argument, "repository_ids and pull_request_id must be present")
          end

          # The upstream service should have already fetched the repo, so we can raise if it's not found
          repo = ::Repositories::Public.get_active_or_deleted!(req.repository_id)
          pull = ::PullRequest.where(repository_id: repo.id, id: req.pull_request_id).first
          authorizer = Authorizer.new(
            token: req.iet,
            repo: repo,
            request: req,
            read_request: req.read_request,
            remote_ip: req.remote_ip, # TODO this could just pull off of the request
          )

          begin
            result = authorizer.access_allowed?(
              :get_pull_request,
              repo: repo,
              resource: pull,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            )
          rescue Platform::Errors::Forbidden => e
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeGetPullRequestResponse.new(
              authorized: false,
              message: e.message,
            )
          end

          MonolithTwirp::Pullsd::Authorization::V1::AuthorizeGetPullRequestResponse.new(
            authorized: result,
            message: authorizer.message,
            status_code: authorizer.status.to_i,
            documentation_url: authorizer.documentation_url,
            errors: authorizer.errors&.map do |error|
              MonolithTwirp::Pullsd::Authorization::V1::ErrorField.new(
                field: error[:field],
                code: error[:code],
                message: error[:message],
              )
            end
          )
        end

        # Public: Implementation of the AuthorizeFollowRepositoryRedirect Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Authorization::V1::AuthorizeFollowRepositoryRedirectRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Authorization::V1::AuthorizeFollowRepositoryRedirectResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Authorization::V1::AuthorizeFollowRepositoryRedirectRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Authorization::V1::AuthorizeFollowRepositoryRedirectResponse, Twirp::Error))
        end
        def authorize_follow_repository_redirect(req, env)
          if unsupported_environment?
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeFollowRepositoryRedirectResponse.new(
              authorized: false,
              message: "Not Found",
              status_code: 404,
            )
          end

          if req.iet == 0 || req.repository_nwo.empty?
            return Twirp::Error.new(:invalid_argument, "iet and repository_nwo must be present")
          end

          redirected_repo = RepositoryRedirect.find_redirected_repository(req.repository_nwo)

          if redirected_repo.nil?
            return Twirp::Error.new(:not_found, "No repository redirect found for #{req.repository_nwo}")
          end

          authorizer = Authorizer.new(
            token: req.iet,
            repo: redirected_repo,
            request: req,
            read_request: true,
            remote_ip: nil,
          )

          begin
            result = authorizer.access_allowed?(:follow_repo_redirect,
              resource: redirected_repo,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          rescue Platform::Errors::Forbidden => e
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeFollowRepositoryRedirectResponse.new(
              authorized: false,
              message: e.message,
            )
          end

          MonolithTwirp::Pullsd::Authorization::V1::AuthorizeFollowRepositoryRedirectResponse.new(
            authorized: result,
            message: authorizer.message,
            status_code: authorizer.status.to_i,
            documentation_url: authorizer.documentation_url,
            errors: authorizer.errors&.map do |error|
              MonolithTwirp::Pullsd::Authorization::V1::ErrorField.new(
                field: error[:field],
                code: error[:code],
                message: error[:message],
              )
            end
          )
        end

        # Public: Implementation of the AuthorizeShowIssue Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Authorization::V1::AuthorizeShowIssueRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Authorization::V1::AuthorizeShowIssueResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Authorization::V1::AuthorizeShowIssueRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Authorization::V1::AuthorizeShowIssueResponse, Twirp::Error))
        end
        def authorize_show_issue(req, env)
          if unsupported_environment?
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeShowIssueResponse.new(
              authorized: false,
              message: "Not Found",
              status_code: 404,
            )
          end

          if req.repository_id == 0 || req.issue_id == 0
            return Twirp::Error.new(:invalid_argument, "repository_id and issue_id must be present")
          end

          repo = ::Repositories::Public.get_active_or_deleted!(req.repository_id)
          issue = ::Issue.where(repository_id: repo.id, id: req.issue_id).first
          authorizer = Authorizer.new(
            token: req.iet,
            repo: repo,
            request: req,
            read_request: req.read_request,
            remote_ip: req.remote_ip,
          )

          begin
            result = authorizer.access_allowed?(
              :show_issue,
              resource: issue,
              repo: repo,
              current_org: repo.owner&.organization? ? repo.owner : nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            )
          rescue Platform::Errors::Forbidden => e
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeShowIssueResponse.new(
              authorized: false,
              message: e.message,
            )
          end

          MonolithTwirp::Pullsd::Authorization::V1::AuthorizeShowIssueResponse.new(
            authorized: result,
            message: authorizer.message,
            status_code: authorizer.status.to_i,
            documentation_url: authorizer.documentation_url,
            errors: authorizer.errors&.map do |error|
              MonolithTwirp::Pullsd::Authorization::V1::ErrorField.new(
                field: error[:field],
                code: error[:code],
                message: error[:message],
              )
            end
          )
        end

        # Public: Implementation of the AuthorizeListPullRequests Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListPullRequestsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListPullRequestsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListPullRequestsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListPullRequestsResponse, Twirp::Error))
        end
        def authorize_list_pull_requests(req, env)
          if unsupported_environment?
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListPullRequestsResponse.new(
              authorized: false,
              message: "Not Found",
              status_code: 404,
            )
          end

          Twirp::Error.new(:unimplemented, "authorize_list_pull_requests is not implemented")
        end

        # Public: Implementation of the AuthorizeListIssues Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListIssuesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListIssuesResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListIssuesRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListIssuesResponse, Twirp::Error))
        end
        def authorize_list_issues(req, env)
          if unsupported_environment?
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListIssuesResponse.new(
              authorized: false,
              message: "Not Found",
              status_code: 404,
            )
          end

          if req.repository_id == 0
            return Twirp::Error.new(:invalid_argument, "repository_id must be present")
          end

          repo = ::Repositories::Public.get_active_or_deleted!(req.repository_id)
          org = repo.owner&.organization? ? repo.owner : nil
          authorizer = Authorizer.new(
            token: req.iet,
            repo: repo,
            request: req,
            read_request: req.read_request,
            remote_ip: req.remote_ip,
          )

          begin
            result = authorizer.access_allowed?(
              :list_issues,
              resource: repo,
              repo: repo,
              organization: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            )
          rescue Platform::Errors::Forbidden => e
            return MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListIssuesResponse.new(
              authorized: false,
              message: e.message,
            )
          end

          MonolithTwirp::Pullsd::Authorization::V1::AuthorizeListIssuesResponse.new(
            authorized: result,
            message: authorizer.message,
            status_code: authorizer.status.to_i,
            documentation_url: authorizer.documentation_url,
            errors: authorizer.errors&.map do |error|
              MonolithTwirp::Pullsd::Authorization::V1::ErrorField.new(
                field: error[:field],
                code: error[:code],
                message: error[:message],
              )
            end
          )
        end

        private

        # Returns true if we're running in multitenant mode.
        # pullsd does not yet support this environment.
        def unsupported_environment?
          GitHub.multi_tenant_enterprise?
        end
      end
    end
  end
end
