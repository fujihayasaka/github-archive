# typed: true
# frozen_string_literal: true

class Orgs::PublisherVerificationController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required
  before_action :marketplace_required, only: [:publisher]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:publisher]

  def publisher # rubocop:todo GitHub/UseRestfulActions
    # check if user has all required fields updated to request a verification
    can_request_verification = current_context.can_request_verification_for_org?
    verification_state = current_context.creator_verification_state?

    render "orgs/publisher_verification/publisher", locals: {
      verification_state: verification_state,
      can_request_verification: can_request_verification
    }
  end

  def apply_verification # rubocop:todo GitHub/UseRestfulActions
    if current_context.organization? && current_context.can_request_verification_for_org?
      current_context.creator_verification_state_update(current_user, Configurable::MarketplaceCreatorVerification::APPLIED)
      redirect_to settings_org_publisher_path
    else
      flash[:error] = "Cannot request for publisher verification."
      redirect_to settings_org_publisher_path
    end
  end

  def cancel_verification # rubocop:todo GitHub/UseRestfulActions
    if current_context.organization?
      current_context.creator_verification_state_update(current_user, Configurable::MarketplaceCreatorVerification::DEFAULT)
      redirect_to settings_org_publisher_path
    else
      flash[:error] = "Cannot cancel request for publisher verification."
      redirect_to settings_org_publisher_path
    end
  end

  private

  def current_context
    this_organization
  end
end
