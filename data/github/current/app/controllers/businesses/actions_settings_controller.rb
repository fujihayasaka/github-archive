# typed: true
# frozen_string_literal: true

class Businesses::ActionsSettingsController < Businesses::BusinessController
  include Actions::LargerRunnersHelper
  before_action :business_owner_required
  before_action :ensure_actions_enabled
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    view = Businesses::Settings::ActionsPoliciesView.new(
      business: this_business,
      query: params["q"],
      current_page: current_page
    )

    if request.xhr?
      headers["Cache-Control"] = "no-cache, no-store"
      render partial: "businesses/settings/actions/orgs", locals: { view: view }
    else
      render "businesses/settings/actions", locals: {
        view: view,
        should_display_custom_images_tab: is_custom_images_enabled?(entity: this_business)
      }
    end
  end

  def update_retention # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = params[:limit]&.to_i || 0
      this_business.set_actions_retention_limit(limit: limit, actor: current_user)
      flash[:notice] = "Retention setting saved."
    rescue Configurable::ActionsRetentionLimit::Error => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to settings_actions_enterprise_path
  end

  def update_cache_size_limit # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = params[:limit]&.to_f.to_i
      if GitHub.enterprise?
        upper_limit = nil
        ActionsCacheUsagePolicy.update_enterprise_cache_usage_policy(current_enterprise: this_business, limit: limit, upper_limit: upper_limit, actor: current_user)
      else
        ActionsPolicyHelper.upsert_cache_storage_policy(this_business, limit, current_user: current_user)
      end
      flash[:notice] = "Cache size settings saved."
    rescue Configurable::ActionsRetentionLimit::Error => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to settings_actions_enterprise_path
  end

  def update_cache_retention # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = params[:limit]&.to_f.to_i
      ActionsPolicyHelper.upsert_cache_retention_policy(this_business, limit, current_user: current_user)
      flash[:notice] = "Cache retention settings saved."
    rescue ActionsCacheUsagePolicy::InvalidLimitError => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to settings_actions_enterprise_path
  end

  def update_cache_size_upper_limit # rubocop:todo GitHub/UseRestfulActions
    begin
      limit = nil
      upper_limit = params[:limit]&.to_f.to_i
      ActionsCacheUsagePolicy.update_enterprise_cache_usage_policy(current_enterprise: this_business, limit: limit, upper_limit: upper_limit, actor: current_user)
      flash[:notice] = "Cache size settings saved."
    rescue Configurable::ActionsRetentionLimit::Error => e
      flash[:error] = "Error saving your changes: #{e.message}"
    end

    redirect_to settings_actions_enterprise_path
  end

  private

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end
end
