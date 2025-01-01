# typed: true
# frozen_string_literal: true

class ActionsCacheController < AbstractRepositoryController
  include ActionsControllerMethods
  include ActionsCacheControllerMethods

  layout "repository"

  before_action :actions_enabled_for_repo?
  before_action :skip_robot
  javascript_bundle :actions, only: [:index]
  stylesheet_bundle :actions
  skip_before_action :cap_pagination, only: [:index]

  before_action :all_color_mode_themes

  preload_features [:actions_workflow_list_pinning], only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Mysql5,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Memex,
  ApplicationRecord::Configurations,
  ApplicationRecord::Spokes,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::RepositoriesActionsChecks,
  ApplicationRecord::Iam,
  ApplicationRecord::Billing,
  only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:index], optional: true

  def index
    caches = cache_items
    max_allowed_page = [1, (caches[:total_count] / DEFAULT_PER_PAGE.to_f).ceil].max
    if current_page > max_allowed_page
      redirect_to url_for(actions_caches_path) + "?page=#{max_allowed_page}"
      return
    end
    cache_usage_stat = cache_usage_stats

    render "actions/cache/index", locals: {
      workflows: workflows,
      required_workflows: workflows(fetch_required_workflows: true),
      workflow_pages_count: workflow_pages_count,
      required_workflow_pages_count: workflow_pages_count(fetch_required_workflows: true),
      cache_item_filters: cache_item_filters,
      cache_usage_stats: cache_usage_stat,
      cache_usage_above_warning_threshold: cache_usage_above_warning_threshold?(cache_usage_stat[:cache_limit], cache_usage_stat[:current_cache_size]),
      cache_items: caches,
      show_only_required_workflows: show_only_required_workflows?,
      show_runners_view: show_runners_view?,
      show_attestations_view: show_attestations_view?,
      allow_pinning: allow_pinning?,
    }
  end

  def destroy
    return render_404 unless current_repository.writable_by?(current_user)

    delete_cache_by_id(params[:cache_id].to_i)
    redirect_to :back
  end

  private

  # Internal: Keep robots off of caches page. Nothing interesting
  # for them here.
  def skip_robot
    render_404 if robot?
  end
end
