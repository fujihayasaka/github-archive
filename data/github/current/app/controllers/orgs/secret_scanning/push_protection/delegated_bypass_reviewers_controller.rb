# typed: strict
# frozen_string_literal: true

class Orgs::SecretScanning::PushProtection::DelegatedBypassReviewersController < Orgs::Controller
  include SecretScanning::Errors

  before_action :login_required
  before_action :manage_security_products_permission_required

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

  sig { void }
  def bypass_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(current_organization, current_user, params)
      end
    end
  end

  private

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
