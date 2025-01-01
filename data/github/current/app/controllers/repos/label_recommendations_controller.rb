# typed: true
# frozen_string_literal: true

class Repos::LabelRecommendationsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  before_action :login_required
  before_action :triagable_required
  before_action :require_metadata_feature_enabled

  allow_verified_fetch only: [:index]

  def index
    sorted_labels = current_repository.sorted_labels_for_recommendations # domain-isolation-query-violation:ignore:packages/issues (select)

    GitHub.dogstats.distribution("repos.label_recommendations.labels_count", sorted_labels.length)

    respond_to do |format|
      format.json do
        render json: { labels: sorted_labels.map { |label| { id: label.global_relay_id, name: label.name, nameHTML: label.name_html, description: label.description, url: label.url, color: label.color } } }
      end
    end
  end

  private def triagable_required
    render_404 unless Issue::PermissionsDependency::repo_triageable_by?(current_user, current_repository)
  end

  private def require_metadata_feature_enabled
    render_404 unless current_user.feature_enabled?(:copilot_auto_assign_metadata)
  end
end
