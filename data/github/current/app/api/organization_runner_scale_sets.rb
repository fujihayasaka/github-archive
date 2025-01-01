# typed: true
# frozen_string_literal: true

class Api::OrganizationRunnerScaleSets < Api::App
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

  post "/organizations/:organization_id/actions/runners/scalesets", operation_id: "actions/create-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      add_runner_scale_set(
        org,
        use_runner_admin: use_runner_admin?(org, is_write: true),
        name: data[:name],
        group_id: data[:runnerGroupId]&.to_i || 1,
        labels: data[:labels],
        runner_setting_hash: data[:runnerSetting]
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  get "/organizations/:organization_id/actions/runners/scalesets", operation_id: "actions/list-runner-scale-sets-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true


    resp = handle_twirp_errors do
      list_runner_scale_sets(
        org,
        name: params[:name],
        group_id: params[:runnerGroupId].to_i,
        page: pagination[:page],
        per_page: pagination[:per_page],
        use_runner_admin: use_runner_admin?(org, is_api_read: true),
        do_experiment: do_runner_admin_experiment?(org),
      )
    end

    deliver :actions_runner_scale_sets_hash, resp
  end

  get "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/get-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      get_runner_scale_set(
        org,
        id: params[:scale_set_id].to_i,
        use_runner_admin: use_runner_admin?(org, is_api_read: true),
        do_experiment: do_runner_admin_experiment?(org),
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  patch "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/update-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      update_runner_scale_set(
        org,
        use_runner_admin: use_runner_admin?(org, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        name: data[:name],
        group_id: data[:runnerGroupId],
        labels: data[:labels],
        runner_setting_hash: data[:runnerSetting]
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  delete "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/delete-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_twirp_errors do
      delete_runner_scale_set(
        org,
        use_runner_admin: use_runner_admin?(org, is_write: true),
        scale_set_id: params[:scale_set_id].to_i
      )
    end

    deliver_empty status: 204
  end

  post "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/sessions", operation_id: "actions/create-runner-scale-set-session-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      add_runner_scale_set_session(
        org,
        use_runner_admin: use_runner_admin?(org, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        session_owner_name: data[:ownerName]
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  patch "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/sessions/:session_id", operation_id: "actions/refresh-runner-scale-set-session-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      refresh_runner_scale_set_session(
        org,
        use_runner_admin: use_runner_admin?(org, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        session_id: params[:session_id]
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  delete "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/sessions/:session_id", operation_id: "actions/delete-runner-scale-set-session-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_twirp_errors do
      delete_runner_scale_set_session(
        org,
        use_runner_admin: use_runner_admin?(org, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        session_id: params[:session_id]
      )
    end

    deliver_empty status: 204
  end

  post "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/generate-jitconfig", operation_id: "actions/generate-runner-scale-set-runner-jitconfig-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      generate_jit_config(
        org,
        use_runner_admin: use_runner_admin?(org, is_write: true),
        scale_set_id: params[:scale_set_id].to_i,
        name: data[:name],
        work_folder: data[:workFolder]
      )
    end

    deliver :actions_runner_scale_set_runner_jitconfig_hash, resp
  end

  get "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/acquirablejobs", operation_id: :internal do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    deliver_empty status: 204
  end

  post "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/acquirejobs", operation_id: :internal,  read_from_replicas: true do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless org.feature_flag_enabled_or_raise?(:runner_scale_set_apis_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 if invalid_jwt_login?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    deliver_empty status: 200
  end
end
