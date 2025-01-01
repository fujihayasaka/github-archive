# typed: true
# frozen_string_literal: true

class SecurityCampaigns::BaseRepositoryController < AbstractRepositoryController
  include ScanningControllerMethods

  before_action :login_required
  before_action :ensure_feature_security_campaigns_enabled
  before_action :ensure_current_repository_private
  before_action :check_code_scanning_write

  private

  def ensure_feature_security_campaigns_enabled
    render_404 unless SecurityCampaigns.enabled?(current_repository.owner)
  end

  def ensure_current_repository_private
    render_404 unless current_repository.private?
  end
end
