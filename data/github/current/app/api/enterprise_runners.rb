# typed: true
# frozen_string_literal: true

class Api::EnterpriseRunners < Api::Enterprise::App
  include Api::App::TwirpHelpers
  include Api::App::ActionsRunnerLabelsHelper
  include ReceiveSchemaWithOpenApi
  include Api::App::ActionsRunnersHelper

  # Create a registration token for enterprise-level runners
  post "/enterprises/:enterprise_id/actions/runners/registration-token", operation_id: "enterprise-admin/create-registration-token-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

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
      Launch::Twirp.self_hosted_runners_client.generate_runner_config(enterprise, name:, runner_group_id:, labels:, work_folder:, github_url:, actor: current_user)
    end

    runner = resp&.runner
    encoded_jit_config = resp&.encoded_jit_config
    deliver :actions_runner_jitconfig_hash, { runner: runner, encoded_jit_config: encoded_jit_config }, { status: 201 }
  end

  # Delete an enterprise-level runner
  delete "/enterprises/:enterprise_id/actions/runners/:runner_id", operation_id: "enterprise-admin/delete-self-hosted-runner-from-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("runner", "delete-enterprise-runner")

    runner_id = params[:runner_id].to_i
    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(enterprise)
      handle_twirp_errors do
        runner_admin_client.delete_runner(
          owner: enterprise,
          runner_id: runner_id,
          actor: current_user
        )
      end
    else
      handle_twirp_errors do
        Launch::Twirp.self_hosted_runners_client.delete_runner(enterprise, runner_id, actor: current_user)
      end
    end

    deliver_empty status: 204
  end

  # Create a remove token for enterprise-level runners
  post "/enterprises/:enterprise_id/actions/runners/remove-token", operation_id: "enterprise-admin/create-remove-token-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

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

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    resp = handle_twirp_errors do
      Launch::Twirp.self_hosted_runners_client.list_downloads(enterprise)
    end

    downloads = resp&.downloads

    deliver :actions_runner_applications_hash, { downloads: downloads }
  end

  # Get all runners
  get "/enterprises/:enterprise_id/actions/runners", operation_id: "enterprise-admin/list-self-hosted-runners-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    attempt_runner_registration_login(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    runners = []
    total = 0

    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      resp = handle_twirp_errors do
        runner_admin_client = GitHub.build_runner_admin_client(enterprise)
        runner_admin_client.list_runners(
          owner: enterprise,
          name: params[:name].nil? ? "" : params[:name],
          page: pagination[:page],
          per_page: pagination[:per_page]
        )
      end
      validate_self_hosted_runners_response!(resp.runners)
      # We map to an Array so pagination works
      runners = paginate_rel(resp.runners.map { |runner| runner })
      total = runners.size
    else
      if GitHub.flipper[:actions_runner_use_pagination].enabled?(enterprise)
        resp = handle_twirp_errors do
          if params[:name].nil?
            Launch::Twirp.self_hosted_runners_client.list_runners(
              enterprise,
              page: pagination[:page],
              per_page: pagination[:per_page]
            )
          else
            Launch::Twirp.self_hosted_runners_client.list_runners(
              enterprise,
              name: params[:name].nil? ? "" : params[:name],
            )

          end
        end
        validate_self_hosted_runners_response!(resp.runners)
        runners = resp.runners
        total = resp.total_runners
      else
        resp = handle_twirp_errors do
          Launch::Twirp.self_hosted_runners_client.list_runners(
            enterprise,
            name: params[:name].nil? ? "" : params[:name])
        end
        validate_self_hosted_runners_response!(resp.runners)
        # We map to an Array so pagination works
        runners = paginate_rel(resp.runners.map { |runner| runner })
        total = runners.total_entries
      end
    end

    deliver :actions_runners_hash, { runners: runners, total_count: total, current_user: current_user }
  end

  # Get a runner
  get "/enterprises/:enterprise_id/actions/runners/:runner_id", operation_id: "enterprise-admin/get-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    runner_id = params[:runner_id].to_i
    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(enterprise)
      resp = handle_twirp_errors do
        runner_admin_client.get_runner(
          owner: enterprise,
          runner_id: runner_id
        )
      end
    else
      resp = handle_twirp_errors do
        Launch::Twirp.self_hosted_runners_client.get_runner(enterprise, runner_id)
      end
    end

    runner = resp&.runner
    deliver_error! 404 unless runner

    deliver :actions_runner_hash, runner
  end

  # Get all labels (system and custom) for a runner
  get "/enterprises/:enterprise_id/actions/runners/:runner_id/labels", operation_id: "enterprise-admin/list-labels-for-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    list_labels_for_runner(enterprise)
  end

  # Add custom labels to a runner
  post "/enterprises/:enterprise_id/actions/runners/:runner_id/labels", operation_id: "enterprise-admin/add-custom-labels-to-self-hosted-runner-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

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
