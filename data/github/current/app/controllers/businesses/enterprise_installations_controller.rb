# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseInstallationsController < Businesses::BusinessController
  include EnterpriseInstallationsHelper

  before_action :business_owner_required
  before_action :eligible_business_required
  before_action :require_valid_installation_token, only: %w(create)
  before_action :require_valid_state, only: %w(create)
  before_action :require_valid_hostname_in_data, only: %w(create)
  before_action :require_valid_server_id_in_data, only: %w(create)
  before_action :business_full_plan_required

  stylesheet_bundle :orgs

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    if request.xhr?
      headers["Cache-Control"] = "no-cache, no-store"
      render partial: "businesses/settings/enterprise_installations/installations_list", locals: {
        installations: installations,
        query: params[:query]
      }
    else
      render "businesses/settings/enterprise_installations/index", locals: {
        installations: installations,
        stats_export_url: stats_export_enterprise_enterprise_installations_url(this_business),
      }
    end
  end

  def create
    if conflict_message
      flash[:error] = conflict_message
      return redirect_to new_enterprise_installation_url(token: params[:token], state: params[:state])
    end

    result = EnterpriseInstallation::Creator.perform(this_business,
      actor: current_user,
      server_data: installations_data,
      entry_point: :business_enterprise_installations_controller_create
    )

    if result.success?
      # TODO: reenable this once https://github.com/github/github/issues/111185 is fixed
      #set_github_app_icon(result.enterprise_installation, current_user)

      redirect_to complete_enterprise_installation_url(result.enterprise_installation, token: params[:token], state: params[:state], client_secret: result.client_secret)
    else
      flash[:error] = "Failed to connect #{installations_data["host_name"]} to the #{this_business.name} enterprise account."
      redirect_to new_enterprise_installation_url(token: params[:token], state: params[:state])
    end
  end

  private

  def eligible_business_required
    render_404 unless this_business.invoiced? || GitHub.multi_tenant_enterprise?
    render_404 if this_business.metered_plan? && !this_business.metered_ghes_eligible?
  end

  memoize def installations
    this_business
      .connected_enterprise_installations
      .for_query(params[:query])
      .paginate(page: current_page)
  end

  memoize def conflict_message
    if EnterpriseInstallation.where(server_id: installations_data["server_id"]).exists?
      "A connection with the server ID #{installations_data["server_id"]} already exists. Please disconnect the existing instance and try again."
    elsif conflicting_installations(this_business, installations_data["host_name"]).exists?
      "A connection with the host name #{installations_data["host_name"]} already exists. Please disconnect the existing instance and try again."
    end
  end
end
