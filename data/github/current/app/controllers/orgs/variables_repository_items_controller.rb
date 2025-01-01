# typed: true
# frozen_string_literal: true

class Orgs::VariablesRepositoryItemsController < Orgs::Controller
  include Variables::Helper
  include Orgs::RepositoryItemsHelper

  before_action :login_required
  before_action :organization_admin_or_actions_variables_fine_grained_permission
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_page_specified

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    selected_repository_ids = []
    if variable_name
      begin
        result = Variables.fetch(
          name: variable_name,
          app: variables_app,
          owner: current_organization,
          actor: current_user,
        )
      rescue Variables::Error
        return render_404
      end

      variable = result.variable

      return render_404 unless variable

      selected_repositories = variable.selected_repositories.map(&:global_id).to_set
      selected_repository_ids = selected_repositories.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    end

    repositories = if current_organization.plan.supports?(:private_secrets_and_variables)
      additional_repositories(selected_repository_ids)
    else
      additional_repositories(selected_repository_ids, public_only: true)
    end

    respond_to do |format|
      format.html do
        render(Organizations::Settings::RepositoryItemsComponent.new(
          organization: current_organization,
          repositories: repositories,
          selected_repositories: [],
          current_page: page,
          total_count: current_organization.repositories.size,
          data_url: data_url,
          aria_id_prefix: aria_id_prefix,
        ), layout: false)
      end
    end
  end

  private

  def data_url
    organization_variables_repository_items_path(current_organization, page: page + 1, app_name: app_name, variable_name: variable_name)
  end

  def aria_id_prefix
    "#{app_name}-#{variable_name}"
  end

  def variable_name
    params[:variable_name]
  end

  def variables_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_variables_app ||= Variables::AppsHelper.app_for(app_name, current_user)
  end
end
