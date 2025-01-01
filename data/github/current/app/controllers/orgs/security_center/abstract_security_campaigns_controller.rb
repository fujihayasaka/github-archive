# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::AbstractSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  extend T::Sig

  before_action :login_required
  before_action :manage_security_products_permission_required
  before_action :security_center_required
  before_action :security_campaigns_required

  private

  def security_campaigns_required
    render_404 unless SecurityCampaigns.enabled?(this_organization)
  end
end
