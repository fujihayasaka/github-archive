# typed: strict
# frozen_string_literal: true

class Businesses::SecretScanning::PushProtection::DelegatedBypassReviewersController < Businesses::BusinessController

  before_action :login_required
  before_action :business_required

  before_action :modify_security_settings_permission_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities

  sig { void }
  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: SecretScanning::Services::DelegatedBypassService.suggested_bypass_reviewers(this_business, current_user, params)
      end
    end
  end

  private

  sig { void }
  def business_required
    render_404 unless this_business
  end

  sig { void }
  def modify_security_settings_permission_required
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user)
    render_404 unless business_authz.can_modify_code_security_settings?
  end
end
