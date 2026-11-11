# typed: strict
# frozen_string_literal: true

class Repos::SecretScanning::PushProtection::ReactBypassController < AbstractRepositoryController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :render_404, unless: :current_user_can_write_to_repo?
  before_action :require_push_protection_enabled
  before_action :require_no_delegated_bypass

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  include SecretScanning::Features::FeatureFlagHelper
  include SecretScanning::Errors

  allow_verified_fetch only: [:promote_bypass]

  track_latency_slo "page-push-protection-allow-secret-cli", 1000, only: [:index]
  track_latency_slo "push-protection-promote-bypass-cli", 650, only: [:promote_bypass]

  sig { returns(String) }
  def self.react_bundle_name
    "secret-scanning-bypass"
  end

  # GET secret_scanning/push_protection/bypass
  sig { void }
  def index
    bypass_placeholder, error_message = SecretScanning::Services::PushProtectionService.get_bypass_placeholder(current_repository, params[:user_id], params[:placeholder_ksuid])
    if bypass_placeholder.nil? || error_message.present?
      if SecretScanning::Services::PushProtectionService.bypass_placeholder_not_found?(error_message)
        return render_404
      end

      log_service_error(
        log_msg: "Service failed to get bypass using placeholder ksuid",
        method_name: __method__.to_s,
        error_message: T.must(error_message),
        ksuid: params[:placeholder_ksuid],
        bypass_reason: nil)
      SecretScanning::Util::Stats.track_graceful_failure(env)

      return render_404
    end

    allow_secret_payload_builder = SecretScanning::Models::React::AllowSecretPayloadBuilder.new(current_repository, current_user)
    payload = allow_secret_payload_builder.page_payload(
      bypass_placeholder: bypass_placeholder,
      limited_user_bypass_experience_only: SecretScanning::Features::User::PushProtection.new(current_user).has_user_bypass_experience?(current_repository)
    )

    render_react_app(
      payload: payload,
      title: "Allow secret",
      page_data: {
        class: "color-bg-subtle",
        hide_header: true
      },
    )
  end

  sig { void }
  def promote_bypass # rubocop:todo GitHub/UseRestfulActions
    if !params[:reason].present? || !params[:reason].in?(SecretScanning::Models::BypassReason.string_values)
      log_service_error(
        log_msg: "Bypass reason params[:reason] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity",
        ksuid: params[:placeholder_ksuid],
        bypass_reason: params[:reason])

      return render plain: "Bypass reason must be provided and must be either false_positive, used_in_tests, or will_fix_later.", status: :unprocessable_entity
    end

    if !params[:placeholder_ksuid].present?
      log_service_error(
        log_msg: "Placeholder ksuid params[:placeholder_ksuid] not provided",
        method_name: __method__.to_s,
        error_message: "unprocessable entity",
        ksuid: params[:placeholder_ksuid],
        bypass_reason: params[:reason])

      return render plain: "Placeholder ksuid for this bypass must be provided.", status: :unprocessable_entity
    end

    reason = params[:reason]
    placeholder_ksuid = params[:placeholder_ksuid]

    result, error_message = SecretScanning::Services::PushProtectionService.promote_bypass(reason, current_repository, current_user, placeholder_ksuid)

    if result.nil? || error_message.present?
      if SecretScanning::Services::PushProtectionService.bypass_placeholder_not_found?(error_message)
        return render plain: error_message, status: :not_found
      end

      log_service_error(
        log_msg: "Service failed to promote bypass and allow secret",
        method_name: __method__.to_s,
        error_message: T.must(error_message),
        ksuid: params[:placeholder_ksuid],
        bypass_reason: params[:reason])

      return render plain: "Failed to promote bypass with ksuid #{placeholder_ksuid}.", status: :internal_server_error
    end

    head :ok
  end

  private

  sig { void }
  def require_push_protection_enabled
    render_404 unless
      SecretScanning::Features::Repo::PushProtection.new(current_repository).enabled? ||
      SecretScanning::Features::User::PushProtection.new(current_user).enabled?
  end


  sig { void }
  def require_no_delegated_bypass
    render_404 if
      SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(current_repository, current_user)
  end

  sig { params(log_msg: String, method_name: String, error_message: String, ksuid: T.nilable(String), bypass_reason: T.nilable(String)).void }
  def log_service_error(log_msg:, method_name:, error_message:, ksuid:, bypass_reason:)
    GitHub.logger.error(
      log_msg,
      "code.namespace": self.class.name,
      "code.function": method_name,
      "controller.name": self.class.name,
      "controller.action": method_name,
      "repo.id": current_repository.id,
      "bypass.placeholder.ksuid": ksuid,
      "bypass.reason": bypass_reason,
      "error.type": SecretScanning::Services::PushProtectionService::BYPASS_ERROR,
      "error.message": error_message
    )
  end
end
