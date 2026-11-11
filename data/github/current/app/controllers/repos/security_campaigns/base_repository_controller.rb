# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::BaseRepositoryController < AbstractRepositoryController
  include CodeScanning::ControllerAccessChecks

  before_action :login_required
  before_action :ensure_feature_security_campaigns_enabled

  private

  def ensure_feature_security_campaigns_enabled
    render_404 unless SecurityCampaigns.enabled?(current_repository.owner)
  end
end
