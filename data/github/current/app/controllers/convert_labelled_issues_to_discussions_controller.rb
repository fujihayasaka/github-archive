# typed: true
# frozen_string_literal: true

class ConvertLabelledIssuesToDiscussionsController < AbstractRepositoryController
  before_action :require_feature
  before_action :login_required
  before_action :require_label
  before_action :require_convertable_label

  layout "repository"


  def create
    category = if params[:category_id]
      current_repository.available_discussion_categories.find_by(id: params[:category_id])
    end

    ConvertLabelledIssuesToDiscussionsJob.perform_later(current_user, label, category: category)

    flash[:notice] = "Open issues with label '#{label.name}' are being converted to discussions."
    redirect_to gh_labels_path(current_repository)
  end

  private

  memoize def label
    current_repository.labels.find_by_id(params[:id])
  end

  def require_label
    render_404 unless label
  end

  def require_convertable_label
    render_404 unless current_repository.can_convert_issues_to_discussions?(current_user)
  end

  def require_feature
    render_404 unless current_repository.discussions_active?
  end
end
