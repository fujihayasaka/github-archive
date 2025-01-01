# typed: true
# frozen_string_literal: true

class Orgs::SecretsRepositoryItemsController < Orgs::Controller
  include Secrets::Helper
  include Orgs::RepositoryItemsHelper

  before_action :login_required
  before_action :organization_admin_or_actions_secrets_fine_grained_permission
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
    only: [:index],
    optional: true

  def index
    selected_repository_ids = []
    if secret_name
      begin
        result = Secrets.fetch(
          name: secret_name,
          app: secrets_app,
          owner: current_organization,
          actor: current_user,
        )
      rescue Secrets::Error
        return render_404
      end

      secret = result.credential

      return render_404 unless secret

      selected_repositories = secret.selected_repositories.map(&:global_id).to_set
      selected_repository_ids = selected_repositories.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    end

    # we don't want to exclude the selected repositories if we're editing a private registry.
    repo_ids_to_exclude = private_registries? ? [] : selected_repository_ids

    repositories = if current_organization.plan.supports?(:private_secrets_and_variables)
      additional_repositories(repo_ids_to_exclude)
    else
      additional_repositories(repo_ids_to_exclude, public_only: true)
    end

    respond_to do |format|
      format.html do
        render(Organizations::Settings::RepositoryItemsComponent.new(
          organization: current_organization,
          repositories: repositories,
          selected_repositories: (private_registries? && selected_repositories) || [],
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
    settings_org_secrets_repository_items_path(current_organization, page: page + 1, app_name: app_name, secret_name: secret_name)
  end

  def aria_id_prefix
    "#{app_name}-#{secret_name}"
  end

  def private_registries?
    app_name == "private_registries"
  end

  def secret_name
    params[:secret_name]
  end

  def secrets_app # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_secrets_app ||= Secrets::AppsHelper.app_for(app_name, current_user)
  end
end
