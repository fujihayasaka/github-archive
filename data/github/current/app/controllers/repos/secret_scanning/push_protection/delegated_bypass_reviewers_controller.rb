# typed: strict
# frozen_string_literal: true

class Repos::SecretScanning::PushProtection::DelegatedBypassReviewersController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :manage_security_products_permission_required
  before_action :require_delegated_bypass_enabled

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Repos::SecretScanning::PushProtection::DelegatedBypassReviewersController#create",
    "Repos::SecretScanning::PushProtection::DelegatedBypassReviewersController#destroy",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true

  include SecretScanning::Features::FeatureFlagHelper
  include SecretScanning::Errors

  allow_verified_fetch only: [:create, :destroy]

  sig { void }
  def create
    # TODO: Stop passing owner_id and owner_scope in body
    if !params.key?(:reviewer_id)
      log_service_error(
        log_msg: "Reviewer ID params[:reviewer_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
    if !params.key?(:reviewer_type)
      log_service_error(
        log_msg: "Reviewer Type params[:reviewer_type] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
    if !params.key?(:user_id)
      log_service_error(
        log_msg: "User ID params[:user_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end

    org = current_repository.organization
    if org.nil?
      log_service_error(
        log_msg: "Invalid repository. Must belong to an organization",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
    if !SecretScanning::Services::DelegatedBypassService.is_valid_reviewer?(Integer(params[:reviewer_id]), params[:reviewer_type], org)
      log_service_error(
        log_msg: "Reviewer is not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end

    reviewer, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(current_repository.id, :REPOSITORY_SCOPE, nil, Integer(params[:reviewer_id]), params[:reviewer_type], params[:user_id])
    if reviewer.nil? || error_message
      flash[:error] = error_message
      return head :internal_server_error
    end
    head :ok
  end

  sig { void }
  def destroy
    # TODO: Stop passing owner_id and owner_scope in body
    if !params.key?(:bypass_reviewer_id)
      log_service_error(
        log_msg: "Bypass Reviewer ID params[:bypass_reviewer_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
    if !params.key?(:user_id)
      log_service_error(
        log_msg: "User ID params[:user_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end

    error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewer(Integer(params[:bypass_reviewer_id]), current_repository.id, :REPOSITORY_SCOPE, params[:user_id])

    if error_message
      flash[:error] = error_message
      log_service_error(
        log_msg: "Service failed to get reviewers using repository ID",
        method_name: __method__.to_s,
        error_message: error_message)
      return head :internal_server_error
    end
    redirect_to :back
  end

  sig { void }
  def bypass_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(current_repository, current_user, params)
      end
    end
  end

  private

  sig { void }
  def require_delegated_bypass_enabled
    render_404 unless
      SecretScanning::Features::Repo::DelegatedBypass.new(current_repository).enabled?
  end

  sig { params(log_msg: String, method_name: String, error_message: String).void }
  def log_service_error(log_msg:, method_name:, error_message:)
    GitHub.logger.error(
      log_msg,
      "code.namespace": self.class.name,
      "code.function": method_name,
      "controller.name": self.class.name,
      "controller.action": method_name,
      "repo.id": current_repository.id,
      "error.type": SecretScanning::Services::DelegatedBypassService::BYPASS_REVIEWER_ERROR,
      "error.message": error_message
    )
  end
end
