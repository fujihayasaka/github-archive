# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependabot-tokens"

module Api::Internal::Twirp::Dependabot
  module Tokens
    module V1
      # Handler for MonolithTwirp::Dependabot::Tokens::V1::TokenAPIService
      class TokenApiHandler < Api::Internal::Twirp::Handler

        class Error < StandardError
          attr_reader :twirp_error
          def initialize(twirp_error)
            super(twirp_error.msg)
            @twirp_error = twirp_error
          end
        end

        allow_access_for :client, allowed_clients: ["dependabot_api"]
        handles_service MonolithTwirp::Dependabot::Tokens::V1::TokenAPIService
        connected_to_writing_for :create_jit_access

        def before_rpc(rack_env, env)
          # proxy the remote ip from the rack environment hash to the request environment hash
          # so we can use it in reflog data
          env["api.remote_ip"] = rack_env["api.remote_ip"]
        end

        sig do
          params(
            req: MonolithTwirp::Dependabot::Tokens::V1::CreateJitAccessRequest,
            env: T.untyped
          ).returns(
            T.any(MonolithTwirp::Dependabot::Tokens::V1::CreateJitAccessResponse, Twirp::Error)
          )
        end
        def create_jit_access(req, env)
          return Twirp::Error.failed_precondition("Dependabot is not available") if GitHub.dependabot_github_app.blank?

          return Twirp::Error.invalid_argument("must be provided", argument: "account_name") unless req.account_name.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "repo_name") unless req.repo_name.present?
          return Twirp::Error.invalid_argument("must be provided", argument: "permissions") unless req.permissions.any?

          target_account = T.cast(
            Users.domain.by_login(req.account_name),
            T.nilable(T.any(User, Organization))
          )
          return Twirp::Error.not_found("account not found") if target_account.nil?

          # NOTE: Must downcast because IRepository doesn't have all the methods needed for these checks.
          target_repo = T.cast( # rubocop:todo GitHub/AvoidCast
            Repositories.domain.by_name_and_owner(name: req.repo_name, owner_id: target_account.id),
            T.nilable(Repository)
          )
          return Twirp::Error.not_found("repository not found") if target_repo.nil?

          if !dependabot_jit_access_allowed?(target_account, target_repo)
            return Twirp::Error.permission_denied("Dependabot cannot access the requested repo on-demand")
          end

          # Ensure the dependabot app is installed on the target account and has
          # access to the requested repository.  If not, trigger a JIT installation.
          installation = find_or_create_dependabot_installation!(target_account, target_repo)

          # generate a token scoped to the requested repository and permissions
          token = generate_scoped_token!(installation, target_repo, permissions: req.permissions.to_h)

          MonolithTwirp::Dependabot::Tokens::V1::CreateJitAccessResponse.new(token:, repository_id: target_repo.id)
        rescue Error => e
          e.twirp_error
        end

        private

        sig do
          params(
            target_account: T.any(User, Organization),
            target_repo: Repository
          ).returns(T::Boolean)
        end
        def dependabot_jit_access_allowed?(target_account, target_repo)
          # Don't JIT install on user repos.  This feature is intended to allow access only to
          # internal repositories, which can only be owned by organizations.
          return false if target_account.is_a?(Business)
          return false unless target_account.organization?

          # don't give access to deleted or locked repositories
          return false if target_repo.deleted? || target_repo.locked?

          visibility = target_repo.visibility
          # Only JIT install for internal repos.  Dependabot should not need to be installed
          # on public repos, and private repos are not supported by this feature.
          return false unless visibility == Repository::INTERNAL_VISIBILITY

          # JIT install is possible on internal repos only when the target is configured for it
          T.cast(target_account, Organization).dependabot_default_repository_access == "internal"
        end

        sig do
          params(
            target_account: T.any(User, Organization),
            target_repo: Repository
          ).returns(IntegrationInstallation)
        end
        def find_or_create_dependabot_installation!(target_account, target_repo)
          installation = GitHub.dependabot_github_app.installations_on(target_account).first
          return installation if installation&.repository_ids&.include?(target_repo.id)

          result = AutomaticAppInstallation.trigger(
            type: :dependabot_jit_access_requested,
            originator: { target_id: target_account.id, repository_id: target_repo.id },
            actor: GitHub.dependabot_github_app_bot,
            async: false
          ).first

          installation_result = result&.installation_result
          raise Error.new(Twirp::Error.internal("Unexpected install failure", reason: result.reason)) if installation_result.nil?

          if (error = installation_result.exception)
            raise Error.new(
              Twirp::Error.internal("Error while granting permissions",
                error: error.to_s,
                reason: installation_result.reason.to_s
              )
            )
          elsif (reason = installation_result.reason)
            raise Error.new(Twirp::Error.failed_precondition("Granting permissions failed", reason: reason.to_s))
          elsif !installation_result.success?
            raise Error.new(Twirp::Error.failed_precondition("Granting permissions failed", reason: "unknown"))
          end

          installation_result.installation
        end

        sig do
          params(
            installation: IntegrationInstallation,
            repository: Repository,
            permissions: T::Hash[T.any(String, Symbol), T.any(String, Symbol)]
          ).returns(String)
        end
        def generate_scoped_token!(installation, repository, permissions: {})
          # Find or create the scoped installation to generate a token for.
          scoped_installation_result = ScopedIntegrationInstallation::Creator.perform_with_cache(
            installation,
            repositories: [repository],
            permissions: permissions,
            entry_point: :twirp_api_dependabot_create_jit_access
          )

          if scoped_installation_result.failed?
            raise Error.new(
              Twirp::Error.failed_precondition("cannot create scoped token", error: scoped_installation_result.error)
            )
          end

          # Generate a token for the scoped installation
          scoped_installation = scoped_installation_result.installation
          token_result = scoped_installation.generate_token
          if !token_result.ok?
            raise Error.new(
              Twirp::Error.failed_precondition("cannot create scoped token", error: scoped_installation_result.error)
            )
          end

          token_result.value.token_value
        end
      end
    end
  end
end
