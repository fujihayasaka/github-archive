# typed: true
# frozen_string_literal: true

class Orgs::MigrationController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required
  before_action :redirect_to_member_privileges

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:customize_member_privileges]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:owners_team]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :owners_team, :customize_member_privileges],
    optional: true

  def index
    render_404
  end

  def customize_member_privileges # rubocop:todo GitHub/UseRestfulActions
    render_404
  end

  def update_member_privileges # rubocop:todo GitHub/UseRestfulActions
    render_404
  end

  def owners_team # rubocop:todo GitHub/UseRestfulActions
    render_404
  end

  private

  # Deprecating the Organization migration pages and functionality -
  # now just redirect the user to the new Organization member
  # privileges page
  def redirect_to_member_privileges
    redirect_to settings_org_member_privileges_path(current_organization)
  end
end
