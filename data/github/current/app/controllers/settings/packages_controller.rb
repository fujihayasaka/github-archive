# typed: true
# frozen_string_literal: true

class Settings::PackagesController < ApplicationController
  include Settings::ControllerMethods
  include Registry::QueryHelper

  before_action :login_required

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PER_PAGE = 30


  def index
    begin
      packages, version_counts, total_unfiltered_count = packages_for_query(
        current_user: current_user,
        query: params[:d_package_name],
        user_session: user_session,
        owner: current_user,
        sort: SORT_TO_QUERY_PARAM["deleted_at_desc"],
        page: current_page,
        per_page: PER_PAGE,
        only_deleted_packages: true,
        excluded_packages: Array.wrap(params[:restored_package])
      )
    rescue ::Search::Query::MaxOffsetError
      return redirect_to settings_packages_path
    end

    return redirect_to settings_packages_path if packages&.size.zero? && current_page > 1

    render "settings/packages/index", locals: {
      deleted_packages: packages,
      total: total_unfiltered_count,
      page: current_page,
      any_package_under_migration: PackageRegistryHelper.has_package_with_pending_migration?(packages),
      package_version_counts: version_counts
    }
  end

  def update
    inherit_access_params = {
      inherit_access: ActiveModel::Type::Boolean.new.cast(settings_params[:containers][:inherit_access])
    }

    if inherit_access_params[:inherit_access]
      current_user.allow_packages_to_inherit_access_from_repo(actor: current_user)
    elsif inherit_access_params[:inherit_access] == false
      current_user.disallow_packages_to_inherit_access_from_repo(actor: current_user)
    end

    redirect_to :back, notice: "Packages settings updated."
  end

  private

  def settings_params
    params.require(:packages).permit(containers: [:inherit_access])
  end
end
