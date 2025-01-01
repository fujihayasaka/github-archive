# typed: false
# frozen_string_literal: true

require "github/launch_client"
require "actions-runner-admin"

# Register self hosted runners for Actions
# This is used by the Action Runner only (https://github.com/actions/runner).
class Api::ActionsRunnerRegistration < Api::App
  include Api::App::TwirpHelpers
  include GitHub::LaunchClient

  rate_limit_as Api::RateLimitConfiguration::ACTIONS_RUNNER_REGISTRATION_FAMILY

  def attempt_login
    @current_user = nil

    input_token = Api::RequestCredentials.token_from_scheme(env, "remoteauth")
    @data = receive(Hash, required: false)
    deliver_error! 422 unless @data

    @runner_owner = find_runner_owner(@data["url"])

    unless @runner_owner
      GitHub.dogstats.increment("actions_runner_registration.attempt_login.no_runner")
      if GitHub.flipper[:actions_hide_runner_owner_message].enabled?
        # This should match the error message for an invalid token to avoid leaking
        # the existence of a runner owner
        # https://github.com/github/c2c-actions/issues/8614
        deliver_error! 404
      else
        deliver_error! 404, message: "Unable to find runner owner."
      end
    end

    scope = @runner_owner.runner_creation_token_scope
    token = User.verify_signed_auth_token(token: input_token, scope: scope)

    deliver_error! 404 unless token.valid?

    @current_user = token.user
    @remote_token_auth = true
  end

  post "/actions/runner-registration", operation_id: :internal do
    @route_owner = "@github/actions-runtime-reviewers"
    deliver_error!(404) unless GitHub.actions_enabled?
    deliver_error!(422) unless @runner_owner

    if @runner_owner.is_a?(Organization)
      control_access :register_actions_runner_org,
        resource: @runner_owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    elsif @runner_owner.is_a?(Business)
      control_access :register_actions_runner_business,
        resource: @runner_owner,
        allow_integrations: false,
        allow_user_via_granular_actor: false,
        enforce_oauth_app_policy: true
    elsif @runner_owner.is_a?(Repository)
      control_access :register_actions_runner_repo,
        resource: @runner_owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      deliver_error!(422, message: "Invalid URL, must be an Enterprise, Organization or Repository.")
    end

    # Result is a GitHub::Launch::Services::Selfhostedrunners::RegisterRunnerResponse,
    # which contains `token` and url which represent a short-lived token from
    # the Actions Service system and the AZP URL the runner can self-register
    # at.
    is_remove_runner_event = @data["runner_event"] == "remove"

    result = handle_twirp_errors do
      if is_remove_runner_event
        Launch::Twirp::self_hosted_runners_client.get_runner_removal_token(@runner_owner, actor: @current_user, instrument: true)
      else
        Launch::Twirp::self_hosted_runners_client.get_runner_registration_token(@runner_owner, actor: @current_user, instrument: true)
      end
    end

    validate_result!(result)
    deliver :actions_runner_registration_hash, {
      url: result.url,
      token: result.token,
      token_schema: result.token_schema,
      use_v2_flow: GitHub.flipper[:actions_runners_use_runner_admin_service].enabled?(@runner_owner)
    }
  end

  # This endpoint is called by the runner to register itself with Runner-Admin
  post "/actions/runners/register", operation_id: :internal do
    @route_owner = "@github/c2c-actions-experience-reviewers"
    deliver_error!(404) unless GitHub.actions_enabled?
    deliver_error!(422) unless @runner_owner
    deliver_error!(404) unless GitHub.flipper[:actions_runners_use_runner_admin_service].enabled?(@runner_owner)

    if @runner_owner.is_a?(Organization)
      control_access :register_actions_runner_org,
        resource: @runner_owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    elsif @runner_owner.is_a?(Business)
      control_access :register_actions_runner_business,
        resource: @runner_owner,
        allow_integrations: false,
        allow_user_via_granular_actor: false,
        enforce_oauth_app_policy: true
    elsif @runner_owner.is_a?(Repository)
      control_access :register_actions_runner_repo,
        resource: @runner_owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      deliver_error!(422, message: "Invalid URL, must be an Enterprise, Organization or Repository.")
    end

    data = @data.deep_symbolize_keys
    group_id = data[:group_id].to_i
    runner_name = data[:name]
    runner_version = data[:version]
    updates_disabled = data[:updates_disabled]
    ephemeral = data[:ephemeral]
    public_key = data[:public_key]
    replace = data[:replace]
    existing_runner_id = data[:runner_id]

    # strip whitespace and remove duplicates
    labels = data[:labels].map { |l| { name: l[:name].strip, type: l[:type] } }.uniq { |l| l[:name].downcase }

    if replace && existing_runner_id.blank?
      deliver_error!(422, message: "Must provide a runner_id to replace a runner")
    end

    runner_admin_client = GitHub.build_runner_admin_client(@runner_owner)

    result = nil

    if replace
      result = runner_admin_client.update_runner(
        owner: @runner_owner,
        runner_id: existing_runner_id,
        group_id: group_id,
        name: runner_name,
        version: runner_version,
        updates_disabled: updates_disabled,
        ephemeral: ephemeral,
        labels: labels,
        public_key: public_key,
        replace_labels: true
      )
    else
      result = runner_admin_client.add_runner(
        owner: @runner_owner,
        group_id: group_id,
        name: runner_name,
        version: runner_version,
        updates_disabled: updates_disabled,
        ephemeral: ephemeral,
        labels: labels,
        public_key: public_key
      )
    end

    if result.call_succeeded?
      add_runner_hash = result.value.to_h
      deliver :actions_runner_admin_registration_hash, add_runner_hash
    else
      deliver_error!(result.status, message: result.options[:message])
    end

  end

  private

  def find_runner_owner(url)
    return nil unless url.present?

    uri = URI(url)
    unless GitHub.enterprise?
      # In certain cases, GitHub.host_name_with_tenant may have a port specified in the hostname. Therefore, we
      # need to strip the port before comparing the the incoming URL's host.
      #
      # Ex:
      #   1. github.localhost:80
      #   2. avocado-gmbh.ghe.localhost:80 (multi-tenant)
      #   3  github.localhost
      # See: https://github.com/github/github/pull/256186#discussion_r1086947370
      tenant_with_hostname = GitHub.host_name_with_tenant
      if Rails.env.development? && tenant_with_hostname.match?(/:\d+\z/)
        tenant_with_hostname = tenant_with_hostname.slice(0..(tenant_with_hostname.index(":") - 1))
      end

      deliver_error!(422, message: "Must use a #{GitHub.host_name} URL") if uri.host != tenant_with_hostname
    end

    _, part_1, part_2, remaining = uri.path.split("/", 3)

    # return early if URL is longer than we expected
    return nil if remaining

    if part_1 == "enterprises"
      Business.find_by(slug: part_2)
    elsif part_1 && part_2
      Repository.nwo("#{part_1}/#{part_2}")
    else
      Organization.find_by(login: part_1)
    end
  end

  def validate_result!(result)
    unless result
      Failbot.report(StandardError.new("no response from register_runner"), launch_selfhostedrunners: GitHub.launch_selfhostedrunners)
      deliver_error!(503, message: "Runner register service unavailable")
    end
  end
end
