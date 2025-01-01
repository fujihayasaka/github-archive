# typed: true
# frozen_string_literal: true

class Api::RepositoryRunners < Api::App
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

  # Create a registration token for repo-level runners
  post "/repositories/:repository_id/actions/runners/registration-token", operation_id: "actions/create-registration-token-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!

    deliver_error! 403, message: "Forbidden", errors: "Repository level self-hosted runners are disabled on this repository" if repo.repo_self_hosted_runners_disabled_by_owner?
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(repo)

    receive_with_schema("runner", "create-registration-token")

    unless repo.actions_app_installed?
      GitHub.dogstats.increment("actions.self_hosted_tenant_setup", tags: ["runner_type:repo"])

      repo.enable_actions_app(
        actor: current_user,
        entry_point: :rest_api_create_registration_token_for_repo_runners
      )
      SetupRepositoryForActionsJob.perform_later(repository: repo)
    end

    expires_at = 1.hour.from_now
    scope = repo.runner_registration_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)
    deliver_raw({ token: token, expires_at: expires_at }, status: 201)
  end

  # Generate a encoded config file for repo-level runners
  post "/repositories/:repository_id/actions/runners/generate-jitconfig", operation_id: "actions/generate-runner-jitconfig-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!

    deliver_error! 409, errors: "GitHub Actions is disabled on this repository" if repo.actions_disabled?
    deliver_error! 403, errors: "Repository level self-hosted runners are disabled on this repository" if repo.repo_self_hosted_runners_disabled_by_owner?
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant!(repo)

    data = receive_with_openapi
    name = data["name"]
    runner_group_id = data["runner_group_id"]
    #sanitize labels before sending to runner
    labels = data["labels"].map(&:strip).uniq(&:downcase)
    work_folder = data["work_folder"].blank? ? "" : data["work_folder"]
    github_url = "#{GitHub.url}/#{repo.owner.display_login}/#{repo.name}"

    resp = handle_twirp_errors do
      generate_jit_runner_config(repo, name:, use_runner_admin: use_runner_admin?(repo, is_write: true), runner_group_id:, labels:, work_folder:, github_url:, actor: current_user)
    end

    runner = resp&.runner
    encoded_jit_config = resp&.encoded_jit_config
    deliver :actions_runner_jitconfig_hash, { runner: runner, encoded_jit_config: encoded_jit_config }, { status: 201 }
  end

  # Get all runners
  get "/repositories/:repository_id/actions/runners", operation_id: "actions/list-self-hosted-runners-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!

    attempt_runner_registration_login(repo)
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :read_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      list_runners_helper(
        repo,
        name: get_name_parameter,
        page: paginator.page,
        per_page: paginator.per_page,
        use_runner_admin: use_runner_admin?(repo, is_api_read: true),
        do_experiment: do_runner_admin_experiment?(repo)
      )
    end

    validate_self_hosted_runners_response!(resp.runners)

    runners = resp.runners
    total = resp.total_runners
    deliver :actions_runners_hash, { runners: runners, total_count: total, current_user: current_user }
  end

  # Create a remove token
  post "/repositories/:repository_id/actions/runners/remove-token", operation_id: "actions/create-remove-token-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!

    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("runner", "create-remove-token")

    expires_at = 1.hour.from_now
    scope = repo.runner_registration_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)
    deliver_raw({ token: token, expires_at: expires_at }, status: 201)
  end

  get "/repositories/:repository_id/actions/runners/downloads", operation_id: "actions/list-runner-applications-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    control_access :read_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      list_runner_downloads(repo, use_runner_admin: use_runner_admin?(repo, is_api_read: true), do_experiment: do_runner_admin_experiment?(repo))
    end

    downloads = resp&.downloads

    deliver :actions_runner_applications_hash, { downloads: downloads }
  end

  # Get a runner
  get "/repositories/:repository_id/actions/runners/:runner_id", operation_id: "actions/get-self-hosted-runner-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :read_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    runner_id = params[:runner_id].to_i

    resp = handle_twirp_errors do
      get_runner(repo, runner_id, use_runner_admin: use_runner_admin?(repo, is_api_read: true), do_experiment: do_runner_admin_experiment?(repo))
    end

    runner = resp&.runner
    deliver_error! 404 unless runner

    deliver :actions_runner_hash, runner
  end

  # Delete a runner
  delete "/repositories/:repository_id/actions/runners/:runner_id", operation_id: "actions/delete-self-hosted-runner-from-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!

    if repo.feature_flag_enabled?(:actions_use_remoteauth_login_for_runner_deletion, default: false)
      attempt_runner_deletion_login(repo)
    end
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    receive_with_schema("runner", "delete-runner")

    runner_id = params[:runner_id].to_i

    handle_twirp_errors do
      resp, _ = delete_runner_helper(repo, runner_id, use_runner_admin: use_runner_admin?(repo, is_write: true), actor: @current_user)
      resp
    end

    deliver_empty status: 204
  end

  # Get all labels (system and custom) for a runner
  get "/repositories/:repository_id/actions/runners/:runner_id/labels", operation_id: "actions/list-labels-for-self-hosted-runner-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :read_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    list_labels_for_runner(repo, is_api_read: true)
  end

  # Add custom labels to a runner
  post "/repositories/:repository_id/actions/runners/:runner_id/labels", operation_id: "actions/add-custom-labels-to-self-hosted-runner-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    add_custom_labels_to_runner(repo)
  end

  # Set (replace all) custom labels for a runner
  put "/repositories/:repository_id/actions/runners/:runner_id/labels", operation_id: "actions/set-custom-labels-for-self-hosted-runner-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    replace_all_custom_labels_for_runner(repo)
  end

  # Remove all custom labels from a runner
  delete "/repositories/:repository_id/actions/runners/:runner_id/labels", operation_id: "actions/remove-all-custom-labels-from-self-hosted-runner-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    remove_all_custom_labels_from_runner(repo)
  end

  # Remove a custom label from a runner
  delete "/repositories/:repository_id/actions/runners/:runner_id/labels/:name", operation_id: "actions/remove-custom-label-from-self-hosted-runner-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    remove_custom_label_from_runner(repo)
  end
end
