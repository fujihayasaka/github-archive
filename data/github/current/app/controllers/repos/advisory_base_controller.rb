# typed: true
# frozen_string_literal: true

class Repos::AdvisoryBaseController < AbstractRepositoryController
  before_action :check_feature_is_enabled

  protected

  memoize def advisory
    current_repository.repository_advisories.find_by!(ghsa_id: params[:id])
  end

  private

  def check_feature_is_enabled
    render_404 unless current_repository.advisories_enabled?
  end

  def authorize_advisory_writable
    render_404 unless advisory.writable_by?(current_user)
  end
end
