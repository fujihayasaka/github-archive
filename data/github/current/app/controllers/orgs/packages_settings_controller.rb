# typed: true
# frozen_string_literal: true

class Orgs::PackagesSettingsController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:index]

  DELETED_PACKAGES_LIMIT = 30

  include Registry::QueryHelper
  include EnterpriseManagedUsersHelper

  before_action :login_required
  before_action :organization_admin_required
  before_action :spammy_behaviour_check


  def index
    begin
      response, packages = packages_for_query(
        query: params[:d_package_name],
        current_user: current_user,
        user_session: user_session,
        owner: current_organization,
        sort: SORT_TO_QUERY_PARAM["deleted_at_desc"],
        page: current_page,
        per_page: DELETED_PACKAGES_LIMIT,
        only_deleted_packages: true,
        excluded_packages: Array.wrap(params[:restored_package])
      )
    rescue ::Search::Query::MaxOffsetError
      return redirect_to settings_org_packages_path
    end

    return redirect_to settings_org_packages_path if packages&.size.zero? && current_page > 1

    render "settings/organization/packages/index", locals: {
      deleted_packages: packages,
      total: response.total,
      page: current_page,
      any_package_under_migration: PackageRegistryHelper.has_package_with_pending_migration?(packages),
      package_version_counts: response.results.each_with_object(Hash.new(0)) do |hit, hash|
        hash[hit.id] = hit.source["versions"].size
      end
    }
  end

  def update
    visibility_params = {
      public: ActiveModel::Type::Boolean.new.cast(settings_params[:containers][:public]),
      internal: ActiveModel::Type::Boolean.new.cast(settings_params[:containers][:internal])
    }
    inherit_access_params = {
      inherit_access: ActiveModel::Type::Boolean.new.cast(settings_params[:containers][:inherit_access])
    }

    if visibility_params[:public]
      current_organization.allow_members_to_publish_public_packages(actor: current_user)
    elsif visibility_params[:public] == false
      current_organization.block_members_from_publishing_public_packages(actor: current_user)
    end

    if visibility_params[:internal]
      current_organization.allow_members_to_publish_internal_packages(actor: current_user)
    elsif visibility_params[:internal] == false
      current_organization.block_members_from_publishing_internal_packages(actor: current_user)
    end

    if inherit_access_params[:inherit_access]
      current_organization.allow_packages_to_inherit_access_from_repo(actor: current_user)
    elsif inherit_access_params[:inherit_access] == false
      current_organization.disallow_packages_to_inherit_access_from_repo(actor: current_user)
    end

    redirect_to :back, notice: "Packages settings updated for this organization."
  end

  private

  def client # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @client ||= PackageRegistry::Twirp.metadata_client
  end

  def spammy_behaviour_check
    render_404 if !PackageRegistryHelper.allow_access_to_actor?(this_organization, current_user)
  end

  def settings_params
    params.require(:packages).permit(containers: [:enabled, :public, :private, :internal, :inherit_access])
  end
end
