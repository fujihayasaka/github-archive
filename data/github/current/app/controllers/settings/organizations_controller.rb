# typed: true
# frozen_string_literal: true

class Settings::OrganizationsController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper
  include InProductTargeting::OrganizationNudgeConcern

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :can_view_organizations_required

  stylesheet_bundle :settings
  javascript_bundle :settings
  javascript_bundle :"sso-orgs-settings-list"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    view = create_view_model(Settings::OrgsView, cap_filter: cap_filter, dismissed_sso_org_ids: dismissed_sso_org_ids, all_orgs_page: params[:all_orgs_page], sso_orgs_page: params[:sso_orgs_page])

    user_is_eligible_for_settings_organization_nudges = current_user&.feature_flag_enabled?(:organization_new_tasks_nudges, default: false)

    # If the current user has the appropriate Feature Flag enabled, we
    # want to split the users' organizations into two groups: ones with nudges and the ones without.
    organizations_with_nudges, organizations_without_nudges = view.memberships.partition do |membership|
      next false unless user_is_eligible_for_settings_organization_nudges
      nudge_to_show_settings_page(current_user, membership.organization) != nil
    end

    render "settings/organizations/index", locals: {
      view: view,
      organizations_with_nudges: organizations_with_nudges,
      organizations_without_nudges: organizations_without_nudges,
      can_move_work: can_move_work?
    }
  end

  private

  def can_move_work?
    return false if GitHub.enterprise?
    return false if current_user.is_enterprise_managed?
    return false unless user_can_create_organizations?

    true
  end

  def can_view_organizations_required
    render_404 if current_user&.is_enterprise_managed? && current_user&.enterprise_managed_business&.seats_plan_basic?
  end
end
