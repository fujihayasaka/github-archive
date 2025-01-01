# typed: true
# frozen_string_literal: true

class Businesses::SecurityAnalysisController < Businesses::BusinessController
  # Access
  before_action :view_permission_required, only: [:index]
  before_action :modify_permission_required, except: [:index]
  before_action :business_full_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:ghas_settings]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:ghas_settings], optional: true

  def index
    render "businesses/settings/security_analysis", locals: {
      business: this_business,
      public_repo_count:,
      repo_count:,
    }
  end

  def update
    error_message = UpdateSecuritySettings.perform(this_business, params, actor: current_user).try(:fetch, :error, nil)
    return redirect_to(:back, flash: { error: error_message }) if error_message.present?

    flash[:notice] = "Security settings updated for #{this_business.name}'s repositories. It may take a few minutes to process."

    redirect_to settings_security_analysis_enterprise_path(this_business, show_update_tip: params[:show_update_tip], show_alert_tip: params[:show_alert_tip])
  end

  def ghas_settings # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Settings::SecurityAnalysisGhasSettingsComponent.new(
          owner: this_business,
          public_repo_count:,
          repo_count:,
          cursor: nil,
          custom_patterns_query: nil
        ), layout: false
      end
    end
  end

  private

  def view_permission_required
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user)
    render_404 unless business_authz.can_view_code_security_settings?
  end

  def modify_permission_required
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user)
    render_404 unless business_authz.can_modify_code_security_settings?
  end

  def public_repo_count
    # equivalent to Repository.where(...).public_scope.count
    repo_counts_by_public&.dig(true) || 0
  end

  def repo_count
    # equivalent to Repository.where(...).count
    repo_counts_by_public&.values&.sum || 0
  end

  memoize def repo_counts_by_public
    this_business.organizations.pluck(:id)
      .in_groups_of(1000, false)
      .map do |org_id_batch|
        Repository
          .where(owner_id: org_id_batch)
          .group(:public)
          .count
      end
      .reduce do |acc, hash|
        # merge hashes by key and sum the values
        acc.merge(hash) { |_key, *values| values.sum }
      end
  end
end
