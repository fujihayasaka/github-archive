# typed: true
# frozen_string_literal: true

require "github/launch_client"

# Register self hosted runners for Actions for a repository
# This API was replaced by Api::ActionsRunnerRegistration to support registering org and enterprise runners
# Updated versions of the runner no longer call this API, but there are some users with very old runner versions
class Api::RepositoryActionsRunners < Api::App
  include Api::App::TwirpHelpers
  include GitHub::LaunchClient

  def attempt_login
    input_token = Api::RequestCredentials.token_from_scheme(env, "remoteauth")
    scope = current_repo.runner_registration_token_scope

    token = User.verify_signed_auth_token(token: input_token, scope: scope)
    if !token.valid?
      if token.expired?
        deliver_error!(401, message: "Token expired.")
      else
        deliver_error! 404
      end
    end

    @current_user = token.user
    @remote_token_auth = true
  end

  post "/repositories/:repository_id/actions-runners/registration", operation_id: :internal do
    @route_owner = "@github/c2c-actions-experience-reviewers"
    deliver_error!(404) unless GitHub.actions_enabled?

    control_access :register_actions_runner_repo,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # result is a GitHub::Launch::Services::Selfhostedrunners::RegisterRunnerResponse,
    # which contains result.token and result.url which represent a short-lived token
    # from the c2c-actions-service system (AZP) and the AZP URL the runner can
    # self-register at.
    result = handle_twirp_errors do
      Launch::Twirp::self_hosted_runners_client.get_runner_registration_token(current_repo, actor: current_user)
    end

    validate_result!(result)
    deliver :actions_runner_registration_hash, {
      url: result.url,
      token: result.token,
      token_schema: result.token_schema,
    }
  end

  private

  def validate_result!(result)
    unless result
      Failbot.report(StandardError.new("no response from register_runner"))
      deliver_error!(503, message: "Runner register service unavailable")
    end
  end
end
