# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::MembersExportController < StafftoolsController
  include OrganizationMembersExportHelper

  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :organization_members_export_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    export = this_user.organization_members_exports.find_by_token!(params[:token])
    render_org_member_export(export)
  end

  def create
    export = this_user.organization_members_exports.create! \
      actor: current_user,
      format: params[:export_format],
      for_site_admin: true
    respond_with_org_member_export \
      export: export,
      export_url: members_export_stafftools_user_url(this_user, token: export.token, format: export.format)
  end

  private

  def organization_members_export_required
    render_404 unless GitHub.organization_members_export_enabled?
  end
end
