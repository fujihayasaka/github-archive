# typed: true
# frozen_string_literal: true

class RegistryTwo::PackageVersionReadmeController < RegistryTwo::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  before_action :redirect_legacy_packages
  before_action :ensure_supported_ecosystem
  before_action :ensure_v2_ui_enabled
  before_action :get_metadata

  def show
    return redirect_to package_two_path if !request.xhr?
    get_package_version.tap do |package_version|
      view = create_view_model(
        RegistryTwo::Packages::ShowView,
        owner: owner,
        package: @metadata.package,
        package_versions: @metadata.package_versions,
        package_version: package_version,
        repository: @metadata.package.repository,
        viewer_is_admin: package_admin?,
        viewer_can_read_repo: current_user_can_read_repo?,
        user_type: params[:user_type] || get_owner_type,
        is_package_page: params[:is_package_page].to_s == "true",
      )
      render partial: "registry_two/packages/package_version_readme", locals: { view: view }
    end
  end

  private

  def get_package_version
    client.get_package_version(
      ecosystem: params[:ecosystem],
      actor: current_user,
      namespace: owner.display_login,
      name: params[:name],
      version_id: params[:version].to_i
    )
  end
end
