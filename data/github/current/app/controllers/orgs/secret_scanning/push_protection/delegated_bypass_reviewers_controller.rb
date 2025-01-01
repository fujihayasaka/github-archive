# typed: strict
# frozen_string_literal: true

class Orgs::SecretScanning::PushProtection::DelegatedBypassReviewersController < Orgs::Controller
  extend T::Sig
  include ApplicationController::VerifiedFetchDependency
  include SecretScanning::Features::FeatureFlagHelper
  include SecretScanning::Errors

  before_action :login_required
  before_action :manage_security_products_permission_required
  before_action :require_delegated_bypass_enabled

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Orgs::SecretScanning::PushProtection::DelegatedBypassReviewersController#create",
    "Orgs::SecretScanning::PushProtection::DelegatedBypassReviewersController#destroy",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true

  allow_verified_fetch only: [:create, :destroy]

  sig { void }
  def index
    if !params.key?(:org_id)
      log_service_error(
        log_msg: "Organization ID params[:org_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end

    bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(:organization, params[:org_id], current_user)
    if error_message
      log_service_error(
        log_msg: "Service failed to get reviewers using organization ID",
        method_name: __method__.to_s,
        error_message: error_message)
      return head :internal_server_error
    end
    result = [bypass_reviewers, error_message]
    head :ok
  end

  sig { void }
  def create
    if !params.key?(:owner_id)
      log_service_error(
        log_msg: "Owner ID params[:owner_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
    if !params.key?(:owner_scope)
      log_service_error(
        log_msg: "Owner Scope params[:owner_scope] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
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

    org = Organization.find_by(id: params[:owner_id])
    if org.nil?
      log_service_error(
        log_msg: "Invalid organization",
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

    reviewer, error_message = SecretScanning::Services::DelegatedBypassService.add_bypass_reviewer(Integer(params[:owner_id]), params[:owner_scope].to_sym, Integer(params[:reviewer_id]), params[:reviewer_type], current_user)
    if reviewer.nil? || error_message
      flash[:error] = error_message
      return head :internal_server_error
    end
    head :ok
  end

  sig { void }
  def destroy
    if !params.key?(:bypass_reviewer_id)
      log_service_error(
        log_msg: "Bypass Reviewer ID params[:bypass_reviewer_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
    if !params.key?(:owner_id)
      log_service_error(
        log_msg: "Owner ID params[:owner_id] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end
    if !params.key?(:owner_scope)
      log_service_error(
        log_msg: "Owner Scope params[:owner_scope] not provided or not valid",
        method_name: __method__.to_s,
        error_message: "unprocessable entity")
      return head :unprocessable_entity
    end

    error_message = SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewer(Integer(params[:bypass_reviewer_id]), Integer(params[:owner_id]), params[:owner_scope], current_user)
    if error_message
      flash[:error] = error_message
      log_service_error(
        log_msg: "Service failed to get reviewers using bypass reviewer ID",
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
        render json: SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(current_organization, current_user, params)
      end
    end
  end

  private

  sig { void }
  def require_delegated_bypass_enabled
    render_404 unless
      SecretScanning::Features::Org::DelegatedBypass.new(current_organization).enabled?
  end

  sig { params(log_msg: String, method_name: String, error_message: String).void }
  def log_service_error(log_msg:, method_name:, error_message:)
    GitHub.logger.error(
      log_msg,
      "code.namespace": self.class.name,
      "code.function": method_name,
      "controller.name": self.class.name,
      "controller.action": method_name,
      "org.id": current_organization.id,
      "error.type": SecretScanning::Services::DelegatedBypassService::BYPASS_REVIEWER_ERROR,
      "error.message": error_message
    )
  end
end
