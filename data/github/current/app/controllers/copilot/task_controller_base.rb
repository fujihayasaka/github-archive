# typed: true
# frozen_string_literal: true

class Copilot::TaskControllerBase < AbstractRepositoryController
  before_action :login_required
  before_action :require_feature_access

  private

  memoize def pull
    PullRequests::PullRequestAccessor.new.by_number(repository_id: current_repository.id, number: params[:id].to_i)
  rescue GH::Errors::ObjectNotFound
    nil
  end

  def require_feature_access
    render_404 unless current_user&.hadron_editor_preview_enabled?
  end

  def blob_limits
    { truncate: false, limit: 2.megabytes }
  end
end
