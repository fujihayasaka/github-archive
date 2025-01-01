# typed: true
# frozen_string_literal: true

class Orgs::Settings::PrivateRepositoryForkingController < Orgs::Controller
  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    if current_organization.supports_enhanced_enterprise_forking_policies?
      policy_value = params[:allow_private_repository_forking_policy]
    end

    success = false

    case params[:allow_private_repository_forking]
    when "1" then
      success = current_organization.allow_private_repository_forking(actor: current_user, policy: policy_value)
    when "0" then
      success = current_organization.block_private_repository_forking(actor: current_user)
    end

    if success
      redirect_to :back, notice: "Repository forking setting updated!"
    else
      flash[:error] = "Repository forking setting not updated. Please try again."
      redirect_to :back
    end
  end
end
