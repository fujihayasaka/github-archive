# typed: true
# frozen_string_literal: true

class Api::OrganizationRunners < Api::App
  include Api::App::TwirpHelpers
  include Api::App::ActionsRunnerLabelsHelper
  include ReceiveSchemaWithOpenApi

  # Create a registration token for org-level runners
  post "/organizations/:organization_id/actions/runners/registration-token", operation_id: "actions/create-registration-token-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

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
      Launch::Twirp.self_hosted_runners_client.generate_runner_config(org, name:, runner_group_id:, labels:, work_folder:, github_url:, actor: current_user)
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

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    receive_with_schema("runner", "delete-org-runner")

    if GitHub.flipper[:actions_runners_use_runner_admin_service].enabled?(org)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      handle_twirp_errors do
        runner_admin_client.delete_runner(
          entity_id: org.next_global_id,
          repo_id: nil,
          org_id: org.next_global_id,
          enterprise_id: org.business&.next_global_id,
          runner_id: params[:runner_id].to_i)
      end
    else
      handle_twirp_errors do
        Launch::Twirp.self_hosted_runners_client.delete_runner(org, params[:runner_id].to_i, actor: current_user)
      end
    end

    deliver_empty status: 204
  end

  # Create a remove token for org-level runners
  post "/organizations/:organization_id/actions/runners/remove-token", operation_id: "actions/create-remove-token-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

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

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    resp = handle_twirp_errors do
      Launch::Twirp.self_hosted_runners_client.list_downloads(org)
    end

    downloads = resp&.downloads

    deliver :actions_runner_applications_hash, { downloads: downloads }
  end

  # Get all runners
  get "/organizations/:organization_id/actions/runners", operation_id: "actions/list-self-hosted-runners-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    attempt_runner_registration_login(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    runners = []
    total = 0
    if GitHub.flipper[:actions_runners_use_runner_admin_service].enabled?(org)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      resp = handle_twirp_errors do
        runner_admin_client.list_runners(
          entity_id: org.next_global_id,
          repo_id: nil,
          org_id: org.next_global_id,
          enterprise_id: org.business&.next_global_id,
          name: params[:name].nil? ? "" : params[:name],
          page: pagination[:page],
          per_page: pagination[:per_page])
      end
      runners = resp.runners
      # TODO(https://github.com/github/actions-runtime/issues/4631): runner admin doesn't return total entries
      total = runners.size
    elsif GitHub.flipper[:actions_runner_use_pagination].enabled?(org)
      resp = handle_twirp_errors do
        if params[:name].nil?
          Launch::Twirp.self_hosted_runners_client.list_runners(
            org,
            page: pagination[:page],
            per_page: pagination[:per_page]
          )
        else
          Launch::Twirp.self_hosted_runners_client.list_runners(
            org,
            name: params[:name].nil? ? "" : params[:name],
          )
        end
      end
      validate_listing!(resp.runners)
      runners = resp.runners
      total = resp.total_runners
    else
      resp = handle_twirp_errors do
        Launch::Twirp.self_hosted_runners_client.list_runners(
          org,
          name: params[:name].nil? ? "" : params[:name],
        )
      end
      validate_listing!(resp.runners)
      # We map to an Array so pagination works
      runners = paginate_rel(resp.runners.map { |runner| runner })
      total = runners.total_entries
    end

    deliver :actions_runners_hash, { runners: runners, total_count: total, current_user: current_user }
  end

  # Get a runner
  get "/organizations/:organization_id/actions/runners/:runner_id", operation_id: "actions/get-self-hosted-runner-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(org)

    resp = handle_twirp_errors do
      Launch::Twirp.self_hosted_runners_client.get_runner(org, params[:runner_id].to_i)
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

  private

  def org_runners_enabled?
    GitHub.actions_enabled?
  end

  def can_use_org_runners?(organization)
    Billing::ActionsPermission.new(organization).status[:error][:reason] != "PLAN_INELIGIBLE"
  end

  def validate_listing!(result)
    unless result
      Failbot.report(StandardError.new("no response from list"), launch_selfhostedrunners: Launch::Twirp.self_hosted_runners_client)
      deliver_error!(503, message: "Runners unavailable. Please try again later.")
    end
  end

  def ensure_tenant!(org)
    handle_twirp_errors do
      Launch::Twirp.deployer_client.setup_tenant(org)
    end
  end

  # calling this method in a route allows the runner to access this endpoint during registration
  # this is needed so the runner can fetch groups and de-dupe runner names during interactive configuration
  def attempt_runner_registration_login(org)
    return unless GitHub.flipper[:actions_runners_use_runner_admin_service].enabled?(org)
    # If the runner is registering via runner-admin, we allow read-only access to certain endpoints
    scope = org.runner_creation_token_scope
    attempt_remote_token_login scope
  end
end
