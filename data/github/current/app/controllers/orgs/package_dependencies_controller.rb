# typed: true
# frozen_string_literal: true

class Orgs::PackageDependenciesController < Orgs::Controller
  include PackageDependencies::SharedActions

  before_action :login_required
  before_action :organization_insights_required
  before_action :organization_dependency_insights_required, only: [
    :package_dependencies_index, :package_dependencies_security_graph, :package_dependencies_licenses_graph,
    :package_dependencies_license_menu_content
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [
      :package_dependencies_index, :package_dependencies_license_menu_content, :package_dependencies_licenses_graph,
      :package_dependencies_security_graph
    ]

  depends_on_clusters ApplicationRecord::Repositories,
    only: [
      :package_dependencies_index, :package_dependencies_licenses_graph, :package_dependencies_license_menu_content
    ]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:package_dependencies_licenses_graph, :package_dependencies_license_menu_content,
           :package_dependencies_index, :package_dependencies_security_graph],
    optional: true

  FLAGS = [
    :policies,
  ]
  preload_features FLAGS, only: [:index, :package_dependencies_index]
  preload_features [:cap_two_factor_filter], only: :package_dependencies_index

  stylesheet_bundle :insights

  def package_dependencies_index # rubocop:todo GitHub/UseRestfulActions
    render_package_dependencies_index(
      cap_filter: cap_filter,
      this_organization: this_organization
    )
  end

  def package_dependencies_security_graph # rubocop:todo GitHub/UseRestfulActions
    render_package_dependencies_security_graph(this_organization: this_organization)
  end

  def package_dependencies_licenses_graph # rubocop:todo GitHub/UseRestfulActions
    render_package_dependencies_licenses_graph(this_organization: this_organization)
  end

  def package_dependencies_license_menu_content # rubocop:todo GitHub/UseRestfulActions
    render_package_dependencies_license_menu_content(this_organization: this_organization)
  end
end
