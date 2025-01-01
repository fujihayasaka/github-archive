# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SecurityConfigurationsController < Stafftools::Businesses::BusinessBaseController
  before_action :dotcom_required

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

  def index
    security_configurations = SecurityConfiguration
      .where(target_type: "global", target_id: 0)
      .or(SecurityConfiguration.where(target_type: "Business", target: this_business))
      .to_a
    configuration_defaults = SecurityConfigurationDefault.find_for(target: this_business, visibility: :all).to_a
    render "stafftools/security_configurations/index",
    layout: "layouts/stafftools/business",
    locals: {
      owner: this_business,
      security_configurations:,
      configuration_defaults:,
      billable_entity: this_business,
    }
  end

  def show
    security_configuration = SecurityConfiguration
      .where(target_type: "global", target_id: 0, id: params[:security_configuration_id])
      .or(SecurityConfiguration.where(target: this_business, id: params[:security_configuration_id]))
      .first
    return render_404 unless security_configuration.present?

    repo_application_counts = RepositorySecurityConfiguration
      .group(:state)
      .where(security_configuration_id: security_configuration.id)
      .count

    render "stafftools/security_configurations/show",
    layout: "layouts/stafftools/business",
      locals: {
        owner: this_business,
        security_configuration:,
        repo_application_counts:,
        billable_entity: this_business,
      }
  end
end
