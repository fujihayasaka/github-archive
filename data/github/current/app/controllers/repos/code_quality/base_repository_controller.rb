# typed: true
# frozen_string_literal: true

class Repos::CodeQuality::BaseRepositoryController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_feature_code_quality_enabled

  private

  def ensure_feature_code_quality_enabled
    render_404 unless CodeQuality.enabled?(current_repository)
  end
end
