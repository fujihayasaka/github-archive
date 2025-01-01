# typed: true
# frozen_string_literal: true

class Stafftools::SecurityConfigurationsController < StafftoolsController
  before_action :ensure_org_not_user

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::SecurityOverviewAnalytics,

  def index
    security_configurations = SecurityConfiguration
      .where(target_type: "global", target_id: 0)
      .or(SecurityConfiguration.where(target: this_user))
      .to_a

    configuration_defaults = SecurityConfigurationDefault.find_for(target: this_user, visibility: :all).to_a

    if this_user.business.present?
      enterprise_security_configurations = SecurityConfiguration
        .where(target: this_user.business)
        .to_a

      enterprise_or_org_security_configurations = SecurityConfiguration
        .where(target_type: "global", target_id: 0)
        .or(SecurityConfiguration.where(target: this_user)
        .or(SecurityConfiguration.where(target: this_user.business)))
        .to_a
    end

    render "stafftools/security_configurations/index",
      layout: "layouts/stafftools/organization/content",
      locals: {
        owner: this_user,
        security_configurations:,
        configuration_defaults:,
        enterprise_security_configurations:,
        enterprise_or_org_security_configurations: enterprise_or_org_security_configurations,
        billable_entity: this_user.billable_owner,
      }
  end

  def show
    security_configuration = SecurityConfiguration
      .where(target_type: "global", target_id: 0, id: params[:security_configuration_id])
      .or(SecurityConfiguration.where(target: this_user, id: params[:security_configuration_id]))
      .first
    return render_404 unless security_configuration.present?

    repo_application_counts = RepositorySecurityConfiguration
      .group(:state)
      .where(security_configuration_id: security_configuration.id, organization_id: this_user.id)
      .count

    render "stafftools/security_configurations/show",
      layout: "layouts/stafftools/organization/content",
      locals: {
        owner: this_user,
        security_configuration:,
        repo_application_counts:,
        billable_entity: this_user.billable_owner,
      }
  end
end
