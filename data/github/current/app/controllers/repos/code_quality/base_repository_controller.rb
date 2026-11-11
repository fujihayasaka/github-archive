# typed: true
# frozen_string_literal: true

class Repos::CodeQuality::BaseRepositoryController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_feature_code_quality_available

  stylesheet_bundle :"code-quality"

  private

  def ensure_feature_code_quality_available
    render_404 unless CodeQuality.available?(current_repository)
  end

  def ensure_feature_code_quality_enabled
    render_404 unless CodeQuality.enabled?(current_repository)
  end

  def check_code_quality_read
    render_404 unless code_quality_readable?
  end

  def check_code_quality_write
    render_404 unless code_quality_writable?
  end

  memoize def code_quality_readable?
    CodeQualityRepositoryPermissions.new(current_repository).code_quality_readable_by?(current_user)
  end

  memoize def code_quality_writable?
    CodeQualityRepositoryPermissions.new(current_repository).code_quality_writable_by?(current_user)
  end
end
