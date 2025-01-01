# typed: true
# frozen_string_literal: true

class Api::EnterpriseRunnerScaleSets < Api::Enterprise::App
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

  post "/enterprises/:enterprise_id/actions/runners/scalesets", operation_id: "enterprise-admin/create-runner-scale-set-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      add_runner_scale_set(
        enterprise,
        name: data[:name],
        group_id: data[:runnerGroupId]&.to_i || 1,
        labels: data[:labels],
        runner_setting_hash: data[:runnerSetting]
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  get "/enterprises/:enterprise_id/actions/runners/scalesets", operation_id: "enterprise-admin/list-runner-scale-sets-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    resp = handle_twirp_errors do
      list_runner_scale_sets(
        enterprise,
        name: params[:name],
        group_id: params[:runnerGroupId].to_i,
        page: pagination[:page],
        per_page: pagination[:per_page]
      )
    end

    deliver :actions_runner_scale_sets_hash, resp
  end

  get "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id", operation_id: "enterprise-admin/get-runner-scale-set-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    resp = handle_twirp_errors do
      get_runner_scale_set(
        enterprise,
        id: params[:runner_scale_set_id].to_i
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  patch "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id", operation_id: "enterprise-admin/update-runner-scale-set-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      update_runner_scale_set(
        enterprise,
        scale_set_id: params[:runner_scale_set_id].to_i,
        name: data[:name],
        group_id: data[:runnerGroupId],
        labels: data[:labels],
        runner_setting_hash: data[:runnerSetting]
      )
    end

    deliver :actions_runner_scale_set_hash, resp.runner_scale_set
  end

  delete "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id", operation_id: "enterprise-admin/delete-runner-scale-set-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    handle_twirp_errors do
      delete_runner_scale_set(
        enterprise,
        scale_set_id: params[:runner_scale_set_id].to_i
      )
    end

    deliver_empty status: 204
  end

  post "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id/sessions", operation_id: "enterprise-admin/create-runner-scale-set-session-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      add_runner_scale_set_session(
        enterprise,
        scale_set_id: params[:runner_scale_set_id].to_i,
        session_owner_name: data[:ownerName]
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  patch "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id/sessions/:session_id", operation_id: "enterprise-admin/refresh-runner-scale-set-session-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    resp = handle_twirp_errors do
      refresh_runner_scale_set_session(
        enterprise,
        scale_set_id: params[:runner_scale_set_id].to_i,
        session_id: params[:session_id]
      )
    end

    deliver :actions_runner_scale_set_session_hash, resp
  end

  delete "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id/sessions/:session_id", operation_id: "enterprise-admin/delete-runner-scale-set-session-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    handle_twirp_errors do
      delete_runner_scale_set_session(
        enterprise,
        scale_set_id: params[:runner_scale_set_id].to_i,
        session_id: params[:session_id]
      )
    end

    deliver_empty status: 204
  end

  post "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id/generate-jitconfig", operation_id: "enterprise-admin/generate-runner-scale-set-runner-jitconfig-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    data = receive_with_openapi.with_indifferent_access

    resp = handle_twirp_errors do
      generate_jit_config(
        enterprise,
        scale_set_id: params[:runner_scale_set_id].to_i,
        name: data[:name],
        work_folder: data[:workFolder]
      )
    end

    deliver :actions_runner_scale_set_runner_jitconfig_hash, resp
  end

  get "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id/acquirablejobs", operation_id: :internal do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    deliver_empty status: 204
  end

  post "/enterprises/:enterprise_id/actions/runners/scalesets/:runner_scale_set_id/acquirejobs", operation_id: :internal, read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise.feature_enabled?(:runner_scale_set_apis_enabled)
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)
    deliver_error! 409, errors: "GitHub Actions is disabled on this enterprise" if enterprise.actions_disabled?
    deliver_error! 404 if invalid_jwt_login?(enterprise)

    validate_scale_set_id!

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    deliver_empty status: 200
  end

  def validate_scale_set_id!
    scale_set_id = params[:runner_scale_set_id]
    if scale_set_id.nil? || scale_set_id.to_i <= 0
      deliver_error! 400, message: "Invalid scale set ID"
    end
  end
end
