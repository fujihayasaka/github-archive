# typed: true
# frozen_string_literal: true

class Api::OrganizationRunnerScaleSets < Api::App
  include Api::App::TwirpHelpers
  include Api::App::ActionsRunnerLabelsHelper
  include ReceiveSchemaWithOpenApi
  include Api::App::ActionsRunnersHelper
  include Api::App::ActionsJwtAuthHelper

  def attempt_login
    attempt_jwt_login
    super unless @current_user
  end

  post "/organizations/:organization_id/actions/runners/scalesets", operation_id: "actions/create-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      GitHub.build_runner_admin_client(org).add_runner_scale_set(
        owner: org,
        name: data[:name],
        group_id: data[:runnerGroupId],
        labels: data[:labels],
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set, status: 201
  end

  get "/organizations/:organization_id/actions/runners/scalesets", operation_id: "actions/list-runner-scale-sets-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true


    resp = handle_twirp_errors do
      GitHub.build_runner_admin_client(org).list_runner_scale_sets(
        owner: org,
        name: params[:name],
        group_id: params[:runnerGroupId].to_i,
        page: pagination[:page],
        per_page: pagination[:per_page]
      )
    end

    deliver :actions_runner_scale_sets_hash, resp
  end

  get "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/get-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true


    resp = handle_twirp_errors do
      GitHub.build_runner_admin_client(org).get_runner_scale_set(
        owner: org,
        scale_set_id: params[:scale_set_id].to_i,
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  patch "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/update-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      GitHub.build_runner_admin_client(org).update_runner_scale_set(
        owner: org,
        scale_set_id: params[:scale_set_id].to_i,
        name: data[:name],
        group_id: data[:runnerGroupId],
        labels: data[:labels],
        runner_setting: data[:runnerSetting],
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  delete "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id", operation_id: "actions/delete-runner-scale-set-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_twirp_errors do
      GitHub.build_runner_admin_client(org).delete_runner_scale_set(
        owner: org,
        scale_set_id: params[:scale_set_id].to_i,
      )
    end

    deliver_empty status: 204
  end

  post "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/sessions", operation_id: "actions/create-runner-scale-set-session-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      GitHub.build_runner_admin_client(org).create_runner_scale_set_session(
        owner: org,
        scale_set_id: params[:scale_set_id].to_i,
        session_owner_name: data[:ownerName],
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  patch "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/sessions/:session_id", operation_id: "actions/refresh-runner-scale-set-session-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    resp = handle_twirp_errors do
      GitHub.build_runner_admin_client(org).refresh_runner_scale_set_session(
        owner: org,
        scale_set_id: params[:scale_set_id].to_i,
        session_id: params[:session_id],
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  delete "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/sessions/:session_id", operation_id: "actions/delete-runner-scale-set-session-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_twirp_errors do
      GitHub.build_runner_admin_client(org).delete_runner_scale_set_session(
        owner: org,
        scale_set_id: params[:scale_set_id].to_i,
      )
    end

    deliver_empty status: 204
  end

  post "/organizations/:organization_id/actions/runners/scalesets/:scale_set_id/generate-jitconfig", operation_id: "actions/generate-runner-scale-set-runner-jitconfig-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_runners_use_runner_admin_service)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      GitHub.build_runner_admin_client(org).generate_jit_runner_config_for_scale_set(
        owner: org,
        scale_set_id: params[:scale_set_id].to_i,
        name: data[:name],
        work_folder: data[:workFolder],
      )
    end

    deliver :actions_runner_scale_set_runner_jitconfig_hash, resp
  end
end
