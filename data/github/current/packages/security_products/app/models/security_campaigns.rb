# typed: strict
# frozen_string_literal: true

# Helper methods on the SecurityCampaigns module
module SecurityCampaigns
  MAX_OPEN_CAMPAIGNS_COUNT = T.let(10, Integer)
  MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE = T.let("This organization has reached the limit of active campaigns. To create a new campaign, first close or delete an existing one.".freeze, String)
  MAX_OPEN_CAMPAIGNS_REOPEN_ERROR_MESSAGE = T.let("This organization has reached the limit of active campaigns. To reopen the campaign, first close or delete an existing one.".freeze, String)
  MAX_OPEN_CAMPAIGNS_PUBLISH_ERROR_MESSAGE = T.let("This organization has reached the limit of active campaigns. To publish the campaign, first close or delete an existing one.".freeze, String)
  OPEN_CAMPAIGNS_CONCURRENT_CREATION_MESSAGE = T.let("Another campaign is being created. Please try again later.".freeze, String)
  CAMPAIGNS_CONCURRENT_REOPEN_MESSAGE = T.let("Another campaign is being reopened. Please try again later.".freeze, String)
  CAMPAIGNS_CONCURRENT_PUBLISH_MESSAGE = T.let("Another campaign is being published. Please try again later.".freeze, String)
  MAX_DRAFT_CAMPAIGNS_COUNT = T.let(10, Integer)
  MAX_DRAFT_CAMPAIGNS_CREATION_ERROR_MESSAGE = T.let("This organization has reached the limit of draft campaigns. To create a new draft campaign, first delete an existing one.".freeze, String)
  DRAFT_CAMPAIGNS_CONCURRENT_CREATION_MESSAGE = T.let("Another draft campaign is being created. Please try again later.".freeze, String)
  MIN_CAMPAIGN_MANAGER_ERROR_MESSAGE = T.let("Campaign manager required.".freeze, String)
  MAX_ALERTS_COUNT = 1000
  MAX_ALERTS_REPOSITORY_COUNT = 1000
  TURBOSCAN_MAX_PAGE_SIZE = 100
  MAX_MANAGER_COUNT = 10
  MAX_CAMPAIGN_MANAGER_ERROR_MESSAGE = T.let("There can only be #{MAX_MANAGER_COUNT} campaign managers.".freeze, String)
  ONBOARDING_DISMISSAL_NOTICE_NAME = :security_campaigns_onboarding
  ONBOARDING_DISMISSAL_NOTICE_PATH = T.let("/settings/dismiss-notice/#{ONBOARDING_DISMISSAL_NOTICE_NAME}", String)

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.enabled?(entity)
    entity.is_a?(Organization) &&
    !entity.feature_flag_enabled?(:security_campaigns_disable, default: false) &&
    !GitHub.enterprise?
  end

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.autofix_generation_enabled?(entity)
    SecurityCampaigns.enabled?(entity) && !entity.feature_flag_enabled?(:security_campaigns_disable_autofix_generation, default: false)
  end

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.issue_creation_enabled?(entity)
    return false unless SecurityCampaigns.enabled?(entity)
    return false if entity.feature_flag_enabled?(:security_campaigns_disable_issue_creation, default: false)

    # As a temporary measure we disable issue creation for organizations that are not fully trusted
    TrustTiers::Tier.for_billable_owner(entity).tier == TrustTiers::Tier::TRUSTED
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def self.show_onboarding_message?(current_user)
    !current_user.dismissed_notice?(ONBOARDING_DISMISSAL_NOTICE_NAME)
  end

  sig { params(org: Organization).returns(T::Enumerable[User]) }
  def self.potential_campaign_managers(org:)
    org.admins + SecurityProduct::SecurityManagers.new(org).users
  end

  sig { params(org: Organization, current_user: User).returns(T::Enumerable[Team]) }
  def self.potential_campaign_manager_teams(org:, current_user:)
    user_visible_teams = org.visible_teams_for(current_user).to_a

    SecurityProduct::SecurityManagers.new(org).teams.filter_map do |team|
      team if user_visible_teams.include?(team)
    end
  end

  sig { returns(Bot) }
  def self.bot!
    bot = Apps::Privileged.attribution_only_system_identity_for(:campaigns)
    raise "GitHub Campaigns bot not found" if bot.nil?
    bot
  end

  sig { returns(String) }
  def self.about_docs_url
    DocsUrlConfig.url_for("code-security/about-security-campaigns")
  end

  sig { returns(String) }
  def self.closing_or_deleting_docs_url
    DocsUrlConfig.url_for("code-security/creating-tracking-security-campaigns-closing-or-deleting-security-campaigns")
  end

  sig { returns(String) }
  def self.best_practice_docs_url
    DocsUrlConfig.url_for("code-security/best-practice-fix-alerts-at-scale-selecting-security-alerts-for-remediation")
  end

  sig { returns(String) }
  def self.fixing_alerts_docs_url
    DocsUrlConfig.url_for("code-security/fixing-alerts-in-security-campaign")
  end

  sig { params(entity: Organization).returns(T::Boolean) }
  def self.notifications_for_code_scanning_read?(entity)
    entity.feature_flag_enabled?(:security_campaigns_notifications_for_code_scanning_read, default: false)
  end
end
