# typed: true
# frozen_string_literal: true

class Orgs::Settings::SecurityAnalysis::GhasReposController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :manage_security_products_permission_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  skip_before_action :cap_pagination

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    return render_404 unless current_organization.advanced_security_purchased?

    sku = GitHub::Turboghas::SKU.from_param(params[:sku])
    current_page = params[:page].to_i
    current_page = 1 if current_page <= 0
    page_size = 10
    repo_data = current_organization.get_advanced_security_repos_and_counts(sku:, page: current_page - 1, page_size: page_size)

    # Have we requested a page greater than the last?
    # This can happen when disabling GHAS, if you disable GHAS on the last repo listed, and that was
    # on a page all of its own
    if repo_data[:repos].empty? && repo_data[:total_repos_count] > 0
      # determine last page and request that instead
      current_page = (repo_data[:total_repos_count] / page_size) + 1
      repo_data = current_organization.get_advanced_security_repos_and_counts(sku:, page: current_page - 1, page_size: page_size)
    end

    # Wrap the data in a WillPaginate::Collection so that we can pass it to
    # the will_paginate helper in the template
    repos = WillPaginate::Collection.create(current_page, page_size, repo_data[:total_repos_count]) do |pager|
      pager.replace(repo_data[:repos])
    end

    renderer = case sku
    when GitHub::Turboghas::SKU::Bundled
      AdvancedSecurityEntitiesLinkRenderer
    when GitHub::Turboghas::SKU::CodeSecurity
      CodeSecurityEntitiesLinkRenderer
    when GitHub::Turboghas::SKU::SecretSecurity
      SecretSecurityEntitiesLinkRenderer
    end

    render partial: "settings/organization/security_analysis_ghas_repos_list", locals: {
      repos: repos,
      total_repos_count: repo_data[:total_repos_count],
      current_organization: current_organization,
      hide_pagination: repo_data[:total_repos_count] <= page_size,
      sku:,
      renderer:,
    }
  end
end
