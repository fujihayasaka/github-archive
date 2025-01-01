# typed: true
# frozen_string_literal: true

class Api::OrganizationRunners < Api::App
  include Api::App::TwirpHelpers
  include Api::App::ActionsRunnerLabelsHelper
  include ReceiveSchemaWithOpenApi
  include Api::App::ActionsRunnersHelper
  include Api::App::ActionsJwtAuthHelper
  include Actions::RunnersClientHelper

  def attempt_login
    super unless GitHub.flipper.feature(:actions_runners_check_jwt_auth_attempt).enabled?
    attempt_actions_jwt_login
    super unless @current_user
  end

  # Create a registration token for org-level runners
  post "/organizations/:organization_id/actions/runners/registration-token", operation_id: "actions/create-registration-token-for-org", read_from_replicas: true do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    receive_with_schema("runner", "create-org-runner-registration-token")

    expires_at = 1.hour.from_now
    scope = org.runner_creation_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)
    deliver_raw({ token: token, expires_at: expires_at }, status: 201)
  end

  # Generate a encoded config file for org-level runners
  post "/organizations/:organization_id/actions/runners/generate-jitconfig", operation_id: "actions/generate-runner-jitconfig-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)
    deliver_error! 409, errors: "GitHub Actions is disabled on this organization" if org.actions_disabled?

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    data = receive_with_openapi
    name = data["name"]
    runner_group_id = data["runner_group_id"]
    #sanitize labels before sending to runner
    labels = data["labels"].map(&:strip).uniq(&:downcase)
    work_folder = data["work_folder"].blank? ? "" : data["work_folder"]
    github_url = "#{GitHub.url}/#{org.display_login}"

    resp = handle_twirp_errors do
      generate_jit_runner_config(org, name:, runner_group_id:, labels:, work_folder:, github_url:, actor: current_user)
    end

    runner = resp&.runner
    encoded_jit_config = resp&.encoded_jit_config
    deliver :actions_runner_jitconfig_hash, { runner: runner, encoded_jit_config: encoded_jit_config }, { status: 201 }
  end

  # Delete an org-level runner
  delete "/organizations/:organization_id/actions/runners/:runner_id", operation_id: "actions/delete-self-hosted-runner-from-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    receive_with_schema("runner", "delete-org-runner")

    runner_id = params[:runner_id].to_i

    handle_twirp_errors do
      delete_runner_helper(org, runner_id, actor: current_user)
    end

    deliver_empty status: 204
  end

  # Create a remove token for org-level runners
  post "/organizations/:organization_id/actions/runners/remove-token", operation_id: "actions/create-remove-token-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    receive_with_schema("runner", "create-org-runner-remove-token")

    expires_at = 1.hour.from_now
    scope = org.runner_deletion_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)
    deliver_raw({ token: token, expires_at: expires_at }, status: 201)
  end

  # List runner downloads
  get "/organizations/:organization_id/actions/runners/downloads", operation_id: "actions/list-runner-applications-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    resp = handle_twirp_errors do
      list_runner_downloads(org, use_runner_admin: use_runner_admin?(org), do_experiment: do_runner_admin_experiment?(org))
    end

    downloads = resp&.downloads

    deliver :actions_runner_applications_hash, { downloads: downloads }
  end

  # Get all runners
  get "/organizations/:organization_id/actions/runners", operation_id: "actions/list-self-hosted-runners-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)
    attempt_runner_registration_login(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)
    use_runner_admin = use_runner_admin?(org)

    resp = handle_twirp_errors do
      list_runners_helper(
        org,
        name: get_name_parameter,
        page: pagination[:page],
        per_page: pagination[:per_page],
        use_runner_admin: use_runner_admin,
        do_experiment: do_runner_admin_experiment?(org)
      )
    end

    validate_self_hosted_runners_response!(resp.runners)

    runners = resp.runners
    total = resp.total_runners
    deliver :actions_runners_hash, { runners: runners, total_count: total, current_user: current_user }
  end

  # Get a runner
  get "/organizations/:organization_id/actions/runners/:runner_id", operation_id: "actions/get-self-hosted-runner-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    runner_id = params[:runner_id].to_i

    resp = handle_twirp_errors do
      get_runner(org, runner_id, use_runner_admin: use_runner_admin?(org), do_experiment: do_runner_admin_experiment?(org))
    end

    runner = resp&.runner
    deliver_error! 404 unless runner

    deliver :actions_runner_hash, runner
  end

  # Get all labels (system and custom) for a runner
  get "/organizations/:organization_id/actions/runners/:runner_id/labels", operation_id: "actions/list-labels-for-self-hosted-runner-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    list_labels_for_runner(org)
  end

  # Add custom labels to a runner
  post "/organizations/:organization_id/actions/runners/:runner_id/labels", operation_id: "actions/add-custom-labels-to-self-hosted-runner-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    add_custom_labels_to_runner(org)
  end

  # Set (replace all) custom labels for a runner
  put "/organizations/:organization_id/actions/runners/:runner_id/labels", operation_id: "actions/set-custom-labels-for-self-hosted-runner-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    replace_all_custom_labels_for_runner(org)
  end

  # Remove all custom labels from a runner
  delete "/organizations/:organization_id/actions/runners/:runner_id/labels", operation_id: "actions/remove-all-custom-labels-from-self-hosted-runner-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    remove_all_custom_labels_from_runner(org)
  end

  # Remove a custom label from a runner
  delete "/organizations/:organization_id/actions/runners/:runner_id/labels/:name", operation_id: "actions/remove-custom-label-from-self-hosted-runner-for-org" do
    deliver_error! 404 unless org_runners_enabled?
    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    remove_custom_label_from_runner(org)
  end
end
