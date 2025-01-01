# typed: true
# frozen_string_literal: true

class Users::GhasActiveCommittersController < Users::Controller

  before_action :require_this_user
  before_action :require_business
  before_action :feature_enabled_for_business?
  before_action :require_advanced_security
  before_action :adminable_by_current_user?

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Configurations,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  only: [:download_active_committers]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:download_active_committers],
    optional: true

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_user),
      filename: "ghas_active_committers_#{this_user.display_login}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  private

  def require_business
    render_404 if managed_business.nil?
  end

  def feature_enabled_for_business?
    render_404 unless AdvancedSecurity::Features::Business::AdvancedSecurity.new(managed_business).feature_available_for_user_repositories?
  end

  def require_advanced_security
    render_404 unless managed_business.advanced_security_purchased?
  end

  def adminable_by_current_user?
    render_404 unless managed_business.billing.manager?(current_user) || managed_business.owner?(current_user)
  end

  def target_for_conditional_access
    this_user
  end

  memoize def managed_business
    biz = this_user.enterprise_managed_business if this_user.is_enterprise_managed?
    biz ||= GitHub.global_business if GitHub.single_business_environment?

    biz
  end
end
