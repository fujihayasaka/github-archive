# typed: true
# frozen_string_literal: true

class Orgs::ImportsController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :org_members_only
  before_action :org_admins_only

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  javascript_bundle "organizations"

  def index
    return render_404 unless GitHub.ldap_sync_enabled?

    ldap_teams = current_organization
      .visible_teams_for(current_user)
      .joins(:ldap_mapping)
      .first(30)

    render "organizations/import", locals: { ldap_teams: ldap_teams }
  end
end
