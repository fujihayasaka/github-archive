# typed: strict
# frozen_string_literal: true

class Settings::EnterprisesController < ApplicationController
  include Settings::ControllerMethods
  include Settings::EnterprisesControllerMethods
  include OrganizationsHelper
  include Site::MicrosoftAnalyticsDependency
  include DigitalFrontDoor::NudgeConcern

  helper_method :show_dfd_new_tasks_nudge?

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :dotcom_required

  # Enable 1DS/MSFT analytics
  before_action :allow_initial_cookie_consent,      only: [:index]
  before_action :enable_microsoft_analytics,        only: [:index]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    @cookie_consent_enabled = T.let(@cookie_consent_enabled, T.nilable(T::Boolean))
    @microsoft_analytics_enabled = T.let(@microsoft_analytics_enabled, T.nilable(T::Boolean))

    all_businesses_for_user = businesses(user: current_user)

    user_is_eligible_for_business_nudges =
      !GitHub.multi_tenant_enterprise? &&
      !GitHub.enterprise? &&
      !current_user&.is_enterprise_managed? &&
      current_user&.feature_enabled?(:dfd_new_tasks)

    business_nudge_variant = get_dfd_new_tasks_variant(current_user)

    # If we are running in Enterprise mode and the current user has the appropriate Feature Flag enabled, we
    # want to split the users' businesses into two groups: ones with nudges and the ones without.
    # The business without nudges will appear together, as usual. Businesses with nudges will be rendered separately
    # with the appropriate Nudge CTAs.
    businesses_with_nudges, businesses_without_nudges = all_businesses_for_user.partition do |business|
      next false unless user_is_eligible_for_business_nudges
      next false if business_nudge_variant <= 0 # either disabled experiment (-1) or the user is in the control group (0)

      nudge_types = [:cb, :org]
      next nudge_types.any? { |type| show_dfd_new_tasks_nudge?(current_user, business, type) }
    end

    render "settings/enterprises/index", locals: {
      businesses: all_businesses_for_user,
      businesses_with_nudges: businesses_with_nudges,
      businesses_without_nudges: businesses_without_nudges,
      show_trial_information: show_trial_information?(user: current_user),
      invitations: invitations(user: current_user),
      show_upsells: show_upsells?(user: current_user),
      enable_msft_analytics: @cookie_consent_enabled && @microsoft_analytics_enabled,
    }
  end
end
