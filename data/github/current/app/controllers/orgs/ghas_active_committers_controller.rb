# typed: true
# frozen_string_literal: true

class Orgs::GhasActiveCommittersController < Orgs::Controller
  before_action :this_organization_required
  before_action :ghas_required
  before_action :org_billing_manager_or_enterprise_admin

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:download_active_committers, :download_repository_active_committers]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:download_active_committers],
    optional: true

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_organization),
      filename: "ghas_active_committers_#{this_organization.display_login}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_repository_active_committers # rubocop:todo GitHub/UseRestfulActions
    repository = this_organization.repositories.where(name: params[:repo_id]).first
    return render_404 if repository.nil?
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_organization, repository_ids: [repository.id]),
      filename: "ghas_active_committers_#{repository.name_with_display_owner}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  private

  def ghas_required
    render_404 if !this_organization.advanced_security_purchased? && !this_organization&.business&.advanced_security_purchased_for_entity?
  end

  def org_billing_manager_or_enterprise_admin
    render_404 if !org_billing_manageable?(this_organization) && !org_in_enterprise_adminable_by_current_user?
  end

  def org_in_enterprise_adminable_by_current_user?
    if this_organization.delegate_billing_to_business?
      this_organization.business.owner?(current_user)
    elsif GitHub.single_business_environment?
      GitHub.global_business.owner?(current_user)
    end
  end
end
