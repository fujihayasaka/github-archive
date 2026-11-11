# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SecurityConfigurationsController < Stafftools::Businesses::BusinessBaseController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::Businesses::SecurityConfigurationsController#unbundle",
    "Stafftools::Businesses::SecurityConfigurationsController#bundle"
  ]

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

  def unbundle # rubocop:disable GitHub/UseRestfulActions
    security_configuration = SecurityConfiguration
      .where(target: this_business, id: params[:security_configuration_id])
      .first
    return render_404 unless security_configuration.present?

    begin
      security_configuration.unbundle!
      flash[:notice] = "Security configuration '#{security_configuration.name}' has been unbundled."
    rescue ArgumentError, ActiveRecord::ActiveRecordError => e
      Failbot.report(e, context: { business_id: this_business.id, security_configuration_id: security_configuration.id })
      flash[:error] = "Failed to unbundle: #{e.message}"
    end

    redirect_to security_configuration_stafftools_enterprise_path(this_business, security_configuration_id: security_configuration.id)
  end

  def bundle # rubocop:disable GitHub/UseRestfulActions
    security_configuration = UnbundledSecurityConfiguration
      .where(target: this_business, id: params[:security_configuration_id])
      .first
    return render_404 unless security_configuration.present?

    begin
      security_configuration.bundle!
      flash[:notice] = "Security configuration '#{security_configuration.name}' has been bundled."
    rescue ArgumentError, ActiveRecord::ActiveRecordError => e
      Failbot.report(e, context: { business_id: this_business.id, security_configuration_id: security_configuration.id })
      flash[:error] = "Failed to bundle: #{e.message}"
    end

    redirect_to security_configuration_stafftools_enterprise_path(this_business, security_configuration_id: security_configuration.id)
  end
end
