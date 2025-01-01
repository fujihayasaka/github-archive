# typed: true
# frozen_string_literal: true

class Api::RepositoryRunnerScaleSets < Api::App
  include Api::App::TwirpHelpers
  include Api::App::ActionsRunnerLabelsHelper
  include ReceiveSchemaWithOpenApi
  include Api::App::ActionsRunnersHelper
  include Api::App::ActionsJwtAuthHelper
  include Actions::RunnerScaleSetsHelper

  def attempt_login
    attempt_actions_jwt_login
    super unless @current_user
  end

  post "/repositories/:repository_id/actions/runners/scalesets", operation_id: "actions/create-runner-scale-set-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      add_runner_scale_set(
        repo,
        use_runner_admin: use_runner_admin?(repo, is_write: true),
        name: data[:name],
        group_id: 1, # repos only have one group
        labels: data[:labels],
        runner_setting_hash: data[:runnerSetting]
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  get "/repositories/:repository_id/actions/runners/scalesets", operation_id: "actions/list-runner-scale-sets-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :read_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      list_runner_scale_sets(
        repo,
        name: params[:name],
        page: pagination[:page],
        per_page: pagination[:per_page],
        use_runner_admin: use_runner_admin?(repo, is_api_read: true),
        do_experiment: do_runner_admin_experiment?(repo),
      )
    end

    deliver :actions_runner_scale_sets_hash, resp
  end

  get "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/get-runner-scale-set-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)

    validate_scale_set_id!

    control_access :read_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_READ_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      get_runner_scale_set(
        repo,
        id: params[:scale_set_id].to_i,
        use_runner_admin: use_runner_admin?(repo, is_api_read: true),
        do_experiment: do_runner_admin_experiment?(repo),
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  patch "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/update-runner-scale-set-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)

    validate_scale_set_id!

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      update_runner_scale_set(
        repo,
        use_runner_admin: use_runner_admin?(repo, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        name: data[:name],
        labels: data[:labels],
        runner_setting_hash: data[:runnerSetting],
        group_id: 1, # repos only have one group
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  delete "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/delete-runner-scale-set-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)
    validate_scale_set_id!

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_twirp_errors do
      delete_runner_scale_set(
        repo,
        use_runner_admin: use_runner_admin?(repo, is_write: true),
        scale_set_id: params[:scale_set_id].to_i
      )
    end

    deliver_empty status: 204
  end

  post "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id/sessions", operation_id: "actions/create-runner-scale-set-session-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)
    validate_scale_set_id!

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      add_runner_scale_set_session(
        repo,
        use_runner_admin: use_runner_admin?(repo, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        session_owner_name: data[:ownerName]
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  patch "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id/sessions/:session_id", operation_id: "actions/refresh-runner-scale-set-session-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)
    validate_scale_set_id!

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      refresh_runner_scale_set_session(
        repo,
        use_runner_admin: use_runner_admin?(repo, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        session_id: params[:session_id]
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  delete "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id/sessions/:session_id", operation_id: "actions/delete-runner-scale-set-session-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)
    validate_scale_set_id!

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_twirp_errors do
      delete_runner_scale_set_session(
        repo,
        use_runner_admin: use_runner_admin?(repo, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        session_id: params[:session_id]
      )
    end

    deliver_empty status: 204
  end

  post "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id/generate-jitconfig", operation_id: "actions/generate-runner-scale-set-runner-jitconfig-for-repo" do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)
    validate_scale_set_id!

    control_access :write_actions_runners_repo,
      resource: repo,
      forbid: repo.public?,
      forbid_message: ActionsCiCdErrors::REPO_RUNNERS_WRITE_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      generate_jit_config(
        repo,
        use_runner_admin: use_runner_admin?(repo, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        name: data[:name],
        work_folder: data[:workFolder]
      )
    end

    deliver :actions_runner_scale_set_runner_jitconfig_hash, resp
  end

  get "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id/acquirablejobs", operation_id: :internal do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)

    control_access :read_admin_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true


    deliver_empty status: 204
  end

  post "/repositories/:repository_id/actions/runners/scalesets/:scale_set_id/acquirejobs", operation_id: :internal, read_from_replicas: true do
    deliver_error! 404 unless repo_runners_enabled?

    repo = find_repo!
    deliver_error! 404 unless repo.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 if invalid_jwt_login?(repo)
    validate_scale_set_id!

    control_access :write_admin_actions_repo,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    deliver_empty status: 200
  end

  def validate_scale_set_id!
    scale_set_id = params[:scale_set_id]
    if scale_set_id.nil? || scale_set_id.to_i <= 0
      deliver_error! 400, message: "Invalid scale set ID"
    end
  end
end
