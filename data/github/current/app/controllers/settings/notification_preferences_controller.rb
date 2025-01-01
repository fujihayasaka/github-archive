# typed: true
# frozen_string_literal: true

class Settings::NotificationPreferencesController < ApplicationController
  include Settings::ControllerMethods
  include Settings::NotificationPreferencesControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :apply_selected_link, only: [:custom_routing, :show]

  stylesheet_bundle :settings
  javascript_bundle :settings
  self.react_bundle_name = "notification-settings"

  SETTINGS_DIFF_METRIC = "notifications.settings.difference"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:custom_routing]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :custom_routing], optional: true

  def custom_routing # rubocop:todo GitHub/UseRestfulActions
    current_user = T.must_because(self.current_user) { "#login_required ensures current_user is not nil" }
    return render_404 if current_user.is_enterprise_managed?

    newsies_available, settings, restricted_org_logins, affiliated_organizations = setting_data

    global_email_address = settings.email(:global).address
    custom_routing_records = affiliated_organizations.map do |org|
      {
        id: org.id,
        login: org.display_login,
        avatarUrl: org.primary_avatar_url(16),
        email: settings.email(org)&.address,
        canRecieveNotifications: org.user_can_receive_email_notifications?(current_user),
        restrictNotificationsToVerifiedDomains: org.restrict_notifications_to_verified_domains?,
        userHasEligibleDomainNotificationEmail: org.user_has_email_eligible_domain_notification_email?(current_user),
        notifiableEmailsForUser: org.notifiable_emails_for(current_user).map { |e| e.email.downcase },
        display: !settings.email(org).fallback?,
      }
    end

    render_react_app(
      payload: {
        newsiesAvailable: newsies_available,
        verificationEnabled: GitHub.email_verification_enabled?,
        organizationRecords: custom_routing_records,
        globalEmailAddress: global_email_address
      },
      title: "Notification settings",
      page_data: { send_vitals: true },
      layout: "layouts/settings/notifications",
    )
  end

  def show
    current_user = T.must_because(self.current_user) { "#login_required ensures current_user is not nil" }
    newsies_available, settings, restricted_org_logins, affiliated_organizations = setting_data

    if GitHub.enterprise?
      continuous_integration_email_enabled = !settings.nil? && settings.continuous_integration_email?
      continuous_integration_failures_only_enabled = !settings.nil? && settings.continuous_integration_failures_only?
    else
      converter = Notifyd::RoutingSettingsService::Converter.new
      begin
        notifyd_routing_settings = Notifyd::RoutingSettingsService.fetch_from_notifyd(current_user, sections: %i[ci])
      rescue Notifyd::NetworkHelper::APIError => e
        flash[:error] = "Oops, something went wrong."
        redirect_back(fallback_location: "/") and return
      end
      newsies_struct = converter.routing_settings_to_newsies_stuct(notifyd_routing_settings.routing_setting)

      continuous_integration_email_enabled = newsies_struct.continuous_integration_email_enabled
      continuous_integration_failures_only_enabled = newsies_struct.continuous_integration_failures_only_enabled
    end
    ci_notifications_enabled = continuous_integration_email_enabled || (settings.present? && settings.continuous_integration_web?)

    payload = {
      newsiesAvailable: newsies_available,
      restrictedOrgLogins: restricted_org_logins,
      autoSubscribeDisabled: GitHub.flipper[:disable_notifications_automatic_watching].enabled?(current_user),
      autoSubscribeRepositories: settings.auto_subscribe_repositories?,
      autoSubscribeTeams: settings.auto_subscribe_teams?,
      continuousIntegrationEmail: continuous_integration_email_enabled,
      continuousIntegrationFailuresOnly: continuous_integration_failures_only_enabled,
      continuousIntegrationWeb: settings.continuous_integration_web?,
      subscribedSettings: settings.subscribed_settings,
      participatingSettings: settings.participating_settings,
      vulnerabilityCli: settings.vulnerability_cli?,
      vulnerabilityEmail: settings.vulnerability_email?,
      vulnerabilityWeb: settings.vulnerability_web?,
      orgDeployKeySettings: settings.org_deploy_key_settings,
      inProductMessages: current_user.subscribed_to_in_product_messages?,
      notifiableEmails: current_user.notifiable_emails.map(&:downcase),
      pullRequestReview: settings.notify_pull_request_review_email?,
      pullRequestPush: settings.notify_pull_request_push_email?,
      ownViaEmail: settings.notify_own_via_email?,
      commentEmail: settings.notify_comment_email?,
      vulnerabilitySubscription: vulnerability_subscription,
      watchingUrl: watching_path,
      actionsUrl: features_actions_path,
      dependabotHelpUrl: DocsUrlConfig.url_for("code-security/about-dependabot-alerts")
    }

    if current_user.is_enterprise_managed?
      payload[:emails] = {
        global: {
          readonly: true,
          address: current_user.profile_email
        }
      }
    else
      payload[:emails] = {
        global: {
          readonly: false,
          address: settings.email(:global).address,
        }
      }
    end

    render_react_app(
      payload: payload,
      title: "Notification Settings",
      page_data: {},
      layout: "layouts/settings/notifications",
    )
  end

  private

  def setting_data
    settings_response = GitHub.newsies.settings(current_user)

    settings, restricted_org_logins, affiliated_organizations = if settings_response.success?
      restricted_orgs_hash = settings_response.value.restricted_organizations.index_by(&:display_login)
      affiliated_orgs = current_user_affiliated_organizations

      affiliated_orgs.each_with_index do |org, index|
        # replace any Organization's in affiliated_orgs with matching ones from
        # restricted_orgs_hash, since the restricted orgs have already
        # evaluated (and memoized the result of) the
        # user_has_email_eligible_domain_notification_email? method (which the
        # view will call again for each org in affiliated_orgs).
        if restricted_orgs_hash.key?(org.display_login)
          affiliated_orgs[index] = restricted_orgs_hash[org.display_login]
        end
      end

      [settings_response.value, restricted_orgs_hash.keys, affiliated_orgs]
    end

    [settings_response.success?, settings, restricted_org_logins, affiliated_organizations]
  end

  def vulnerability_subscription
    return "" unless SecurityProduct::VulnerabilityAlerts.enabled_for_instance?

    current_user = T.must_because(self.current_user) { "#login_required ensures current_user is not-nil" }
    subscription = NewsletterSubscription.find_by(
      user_id: current_user.id,
      name: "vulnerability",
    )
    if subscription&.active? && subscription.kind == "weekly"
      "weekly"
    elsif subscription&.active? && subscription.kind == "daily"
      "daily"
    else
      ""
    end
  end

  def apply_selected_link
    @selected_link = :notifications
  end
end
