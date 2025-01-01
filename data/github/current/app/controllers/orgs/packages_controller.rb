# typed: true
# frozen_string_literal: true

class Orgs::PackagesController < Orgs::Controller
  before_action :check_packages_availability
  before_action :spammy_behaviour_check
  skip_before_action :cap_pagination

  include Registry::QueryHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PAGE_SIZE = 30 # 10 rows of 3 columns, 15 rows of 2 columns, 30 rows of 1 column

  def index
    # if Org is within Enterprise Managed User enabled business
    # it is NOT viewable by non Enterprise-Managed users (including anonymous
    # requests)
    if this_organization.enterprise_managed_user_enabled?
      return render_404 unless current_user&.enterprise_managed_business == this_organization.business
    end

    respond_to do |format|
      format.html do
        if request.xhr? || pjax?
          render partial: "registry/packages/filtered_packages", locals: {
            owner: this_organization,
            packages: packages,
            params: params
          }
        elsif this_organization.has_sdn_new_org_with_free_plan_restriction?
          render "orgs/restricted_org_notice", locals: {
            target: this_organization,
            header_view: create_view_model(Orgs::HeaderView, organization: this_organization),
            selected_nav_item: :packages
          }
        else
          view = create_view_model(
            Orgs::Packages::IndexView,
            organization: this_organization,
            phrase: query
          )
          render "orgs/packages/index", locals: { packages: packages, view: view }
        end
      end
    end
  end

  private

  def query
    raw_query = params[:q]
    raw_query.strip if raw_query.is_a?(String)
  end

  def packages
    return [] if PackageRegistryHelper.show_packages_blankslate?
    repository = params[:repo_name].present? && this_organization.repositories.find_by(name: params[:repo_name])
    results, packages = packages_for_query(
      current_user: current_user,
      user_session: user_session,
      owner: this_organization,
      repo_id: repository && (repository.public? || repository.readable_by?(current_user)) ? repository.id : nil,
      query: query,
      package_type: ecosystem_param,
      visibility: visibility_param,
      sort: sort_param,
      page: current_page,
      per_page: PAGE_SIZE,
      use_cached_versions: true,
    )

    WillPaginate::Collection.create(current_page, PAGE_SIZE) do |pager|
      pager.replace(packages)
      pager.total_entries ||= results.total_entries
    end
  end

  def spammy_behaviour_check
    render_404 if !PackageRegistryHelper.allow_access_to_actor?(this_organization, current_user)
  end

  def check_packages_availability
    render_404 unless PackageRegistryHelper.show_packages?
  end
end
