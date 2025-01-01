# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::CachesController < Orgs::Controller
  DEFAULT_PER_PAGE = 25

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  skip_before_action :cap_pagination, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  stylesheet_bundle :settings

  def index
    page = current_page
    per_page = DEFAULT_PER_PAGE
    sort = params.fetch(:sort, "size-desc")
    if sort_labels.exclude? sort
      sort = "size-desc"
    end
    repo = params.fetch(:qr, nil)
    repo = nil if repo.blank?

    cache_usage_by_repo_with_repo_details = ActionsCacheUsageHelper.get_org_cache_usage_with_repo_details(current_organization.id, page, per_page, sort, repo)
    cache_usage_org = ActionsCacheUsageHelper.get_org_cache_usage(current_organization.id, repo)

    cache_usage_summary_string = cache_usage_by_repo_with_repo_details.empty? ? "0 caches" : "#{cache_usage_by_repo_with_repo_details.total_entries} #{'repository'.pluralize(cache_usage_by_repo_with_repo_details.total_entries)} with #{cache_usage_org.total_active_caches_count.to_fs(:rounded, precision: 0)} active #{'cache'.pluralize(cache_usage_org.total_active_caches_count)}"

    max_allowed_page = [1, (cache_usage_by_repo_with_repo_details.total_entries / DEFAULT_PER_PAGE.to_f).ceil].max
    if page > max_allowed_page
      redirect_to settings_org_actions_caches_path(sort: params[:sort], qr: params[:qr], page: max_allowed_page)
      return
    end

    render "settings/organization/actions/caches", locals: {
      cache_usage_by_repo: cache_usage_by_repo_with_repo_details,
      cache_usage_org: cache_usage_org,
      cache_usage_summary_string: cache_usage_summary_string,
      org: current_organization,
      sort: sort,
      repo: repo,
    }
  end

  def update_cache_size # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = params[:limit]&.to_f.to_i
      if GitHub.enterprise?
        ActionsCacheUsagePolicy.update_organization_cache_usage_policy(current_organization: current_organization, limit: limit, actor: current_user)
      else
        ActionsPolicyHelper.upsert_cache_storage_policy(current_organization, limit, current_user: current_user)
      end
      flash[:notice] = "Cache size saved."
    rescue ActionsCacheUsagePolicy::InvalidLimitError => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to settings_org_actions_path
  end

  def update_cache_retention # rubocop:todo GitHub/UseRestfulActions
    begin
      retain_for = params[:limit]&.to_i
      ActionsPolicyHelper.upsert_cache_retention_policy(current_organization, retain_for, current_user: current_user)
      flash[:notice] = "Cache retention saved."
    rescue ArgumentError => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to settings_org_actions_path
  end

  private

  def sort_labels
    %w[size-desc size-asc]
  end
end
