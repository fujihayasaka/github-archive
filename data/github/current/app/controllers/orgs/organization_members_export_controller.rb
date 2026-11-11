# typed: true
# frozen_string_literal: true

class Orgs::OrganizationMembersExportController < Orgs::Controller
  include OrganizationMembersExportHelper

  before_action :organization_admin_required, :organization_members_export_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    export = this_organization.organization_members_exports.find_by_token!(params[:token])
    render_org_member_export(export)
  end

  def create
    options = {
      actor: current_user,
      format: params[:export_format],
    }
    export = this_organization.organization_members_exports.create(options)
    respond_with_org_member_export \
      export: export,
      export_url: org_members_export_url(token: export.token, format: export.format)
  end
end
