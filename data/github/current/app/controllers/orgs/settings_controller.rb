# typed: true
# frozen_string_literal: true

# Settings related to Organizations, as opposed to Users.
#
# Related security issue: https://github.com/github/github/issues/125004
#
# Actions for this controller previously lived in the SettingsController. Given
# the above issue, they have been extracted out to into this controller pretty
# much whole cloth. For a more acturate git history, check the Settings
# Controller.
class Orgs::SettingsController < Orgs::Controller
  include BusinessesHelper
  include SharedBusinessActions

  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required, except: :index
  before_action :organization_setting_fgp_required, only: :index
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    if current_organization.has_sdn_new_org_with_free_plan_restriction?
      return render "orgs/restricted_org_notice", locals: {
        target: current_organization,
        header_view: create_view_model(Orgs::HeaderView, organization: current_organization),
        selected_nav_item: :settings
      }
    end

    if current_organization.adminable_by?(current_user)
      render "settings/organization/profile"
    else
      render "settings/organization/fgp_settings"
    end
  end
end
