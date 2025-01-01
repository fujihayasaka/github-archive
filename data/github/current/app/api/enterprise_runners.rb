# typed: true
# frozen_string_literal: true

class Api::EnterpriseRunners < Api::Enterprise::App
  include Api::App::TwirpHelpers
  include Api::App::ActionsRunnerLabelsHelper
  include ReceiveSchemaWithOpenApi
  include Api::App::ActionsRunnersHelper
  include Api::App::ActionsJwtAuthHelper
  include Actions::RunnersClientHelper

  def attempt_login
    super unless FeatureFlag.vexi.enabled_or_raise?(:actions_runners_check_jwt_auth_attempt) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    attempt_actions_jwt_login
    super unless @current_user
  end

  # Create a registration token for enterprise-level runners
  post "/enterprises/:enterprise_id/actions/runners/registration-token", operation_id: "enterprise-admin/create-registration-token-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("runner", "create-enterprise-runner-registration-token")

    expires_at = 1.hour.from_now
    scope = enterprise.runner_creation_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)
    deliver_raw({ token: token, expires_at: expires_at }, status: 201)
  end

  # Generate a encoded config file for enterprise-level runners
  post "/enterprises/:enterprise_id/actions/runners/generate-jitconfig", operation_id: "actions/generate-runner-jitconfig-for-enterprise" do
    enterprise = find_enterprise!

    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    data = receive_with_openapi
    name = data["name"]
    runner_group_id = data["runner_group_id"]
    #sanitize labels before sending to runner
    labels = data["labels"].map(&:strip).uniq(&:downcase)
    work_folder = data["work_folder"].blank? ? "" : data["work_folder"]
    github_url = "#{GitHub.url}/enterprises/#{enterprise.slug}"

    resp = handle_twirp_errors do
      generate_jit_runner_config(enterprise, name:, use_runner_admin: use_runner_admin?(enterprise, is_write: true), runner_group_id:, labels:, work_folder:, github_url:, actor: current_user)
    end

    runner = resp&.runner
    encoded_jit_config = resp&.encoded_jit_config
    deliver :actions_runner_jitconfig_hash, { runner: runner, encoded_jit_config: encoded_jit_config }, { status: 201 }
  end

  # Delete an enterprise-level runner
  delete "/enterprises/:enterprise_id/actions/runners/:runner_id", operation_id: "enterprise-admin/delete-self-hosted-runner-from-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    if enterprise.feature_flag_enabled?(:actions_use_remoteauth_login_for_runner_deletion, default: false)
      attempt_runner_deletion_login(enterprise)
    end
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("runner", "delete-enterprise-runner")

    runner_id = params[:runner_id].to_i

    handle_twirp_errors do
      resp, _ = delete_runner_helper(enterprise, runner_id, use_runner_admin: use_runner_admin?(enterprise, is_write: true), actor: current_user)
      resp
    end

    deliver_empty status: 204
  end

  # Create a remove token for enterprise-level runners
  post "/enterprises/:enterprise_id/actions/runners/remove-token", operation_id: "enterprise-admin/create-remove-token-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("runner", "create-enterprise-runner-remove-token")

    expires_at = 1.hour.from_now
    scope = enterprise.runner_deletion_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)
    deliver_raw({ token: token, expires_at: expires_at }, status: 201)
  end

  # List runner downloads
  get "/enterprises/:enterprise_id/actions/runners/downloads", operation_id: "enterprise-admin/list-runner-applications-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    resp = handle_twirp_errors do
      list_runner_downloads(enterprise, use_runner_admin: use_runner_admin?(enterprise, is_api_read: true), do_experiment: do_runner_admin_experiment?(enterprise))
    end

    downloads = resp&.downloads

    deliver :actions_runner_applications_hash, { downloads: downloads }
  end

  # Get all runners
  get "/enterprises/:enterprise_id/actions/runners", operation_id: "enterprise-admin/list-self-hosted-runners-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    attempt_runner_registration_login(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    resp = handle_twirp_errors do
      list_runners_helper(
        enterprise,
        name: get_name_parameter,
        page: pagination[:page],
        per_page: pagination[:per_page],
        use_runner_admin: use_runner_admin?(enterprise, is_api_read: true),
        do_experiment: do_runner_admin_experiment?(enterprise)
      )
    end

    validate_self_hosted_runners_response!(resp.runners)

    runners = resp.runners
    total = resp.total_runners
    deliver :actions_runners_hash, { runners: runners, total_count: total, current_user: current_user }
  end

  # Get a runner
  get "/enterprises/:enterprise_id/actions/runners/:runner_id", operation_id: "enterprise-admin/get-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    runner_id = params[:runner_id].to_i

    resp = handle_twirp_errors do
      get_runner(enterprise, runner_id, use_runner_admin: use_runner_admin?(enterprise, is_api_read: true), do_experiment: do_runner_admin_experiment?(enterprise))
    end

    runner = resp&.runner
    deliver_error! 404 unless runner

    deliver :actions_runner_hash, runner
  end

  # Get all labels (system and custom) for a runner
  get "/enterprises/:enterprise_id/actions/runners/:runner_id/labels", operation_id: "enterprise-admin/list-labels-for-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    list_labels_for_runner(enterprise, is_api_read: true)
  end

  # Add custom labels to a runner
  post "/enterprises/:enterprise_id/actions/runners/:runner_id/labels", operation_id: "enterprise-admin/add-custom-labels-to-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    add_custom_labels_to_runner(enterprise)
  end

  # Set (replace all) custom labels for a runner
  put "/enterprises/:enterprise_id/actions/runners/:runner_id/labels", operation_id: "enterprise-admin/set-custom-labels-for-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    replace_all_custom_labels_for_runner(enterprise)
  end

  # Remove all custom labels from a runner
  delete "/enterprises/:enterprise_id/actions/runners/:runner_id/labels", operation_id: "enterprise-admin/remove-all-custom-labels-from-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    remove_all_custom_labels_from_runner(enterprise)
  end

  # Remove a custom label from a runner
  delete "/enterprises/:enterprise_id/actions/runners/:runner_id/labels/:name", operation_id: "enterprise-admin/remove-custom-label-from-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    remove_custom_label_from_runner(enterprise)
  end

end
