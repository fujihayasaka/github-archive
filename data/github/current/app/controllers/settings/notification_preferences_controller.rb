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
    newsies_available, newsies_settings, restricted_org_logins, affiliated_organizations = setting_data
    settings = Notifications::Settings.settings(current_user, settings: newsies_settings)

    watcher = []
    watcher << "email" if settings&.watcher&.email
    watcher << "web" if settings&.watcher&.web

    participant = []
    participant << "email" if settings&.participant&.email
    participant << "web" if settings&.participant&.web

    payload = {
      newsiesAvailable: newsies_available && settings.present?,
      restrictedOrgLogins: restricted_org_logins,
      autoSubscribeDisabled: FeatureFlag.vexi.enabled?(:disable_notifications_automatic_watching, current_user, default: true),
      autoSubscribeRepositories: newsies_settings.auto_subscribe_repositories?,
      autoSubscribeTeams: newsies_settings.auto_subscribe_teams?,
      continuousIntegrationEmail: settings&.actions&.email,
      continuousIntegrationFailuresOnly: settings&.actions&.failures,
      continuousIntegrationWeb: settings&.actions&.web,
      subscribedSettings: watcher,
      participatingSettings: participant,
      vulnerabilityCli: newsies_settings.vulnerability_cli?,
      vulnerabilityEmail: settings&.vulnerability&.email,
      vulnerabilityWeb: settings&.vulnerability&.web,
      orgDeployKeySettings: newsies_settings.org_deploy_key_settings,
      inProductMessages: current_user.subscribed_to_in_product_messages?,
      securityCampaignsEnabled: !GitHub.enterprise?,
      securityCampaignEmails: settings&.security_campaigns&.email,
      notifiableEmails: current_user.notifiable_emails.map(&:downcase),
      pullRequestReview: settings&.pull_request_review_email,
      pullRequestPush: settings&.pull_request_push_email,
      ownViaEmail: settings&.own_email,
      commentEmail: settings&.issue_comment_email,
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
          address: newsies_settings.email(:global).address,
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
