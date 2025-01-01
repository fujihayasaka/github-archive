# typed: strict
# frozen_string_literal: true

# Helper methods on the SecurityCampaigns module
module SecurityCampaigns
  MAX_CAMPAIGNS_COUNT = T.let(10, Integer)
  MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE = T.let("This organization has reached the limit of active campaigns. To create a new campaign, first close or delete an existing one.".freeze, String)
  MAX_CAMPAIGNS_REOPEN_ERROR_MESSAGE = T.let("This organization has reached the limit of active campaigns. To re-open the campaign, first close or delete an existing one.".freeze, String)
  CAMPAIGNS_CONCURRENT_CREATION_MESSAGE = T.let("Another campaign is being created. Please try again later.".freeze, String)
  CAMPAIGNS_CONCURRENT_REOPEN_MESSAGE = T.let("Another campaign is being re-opened. Please try again later.".freeze, String)
  MAX_ALERTS_COUNT = 1000
  TURBOSCAN_MAX_PAGE_SIZE = 100
  ONBOARDING_DISMISSAL_NOTICE_NAME = :security_campaigns_onboarding
  ONBOARDING_DISMISSAL_NOTICE_PATH = T.let("/settings/dismiss-notice/#{ONBOARDING_DISMISSAL_NOTICE_NAME}", String)

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.enabled?(entity)
    entity.is_a?(Organization) && entity.feature_enabled?(:security_campaigns) && !entity.feature_enabled?(:security_campaigns_disable)
  end

  sig { params(entity: Organization).returns(T::Boolean) }
  def self.api_enabled?(entity)
    enabled?(entity) && entity.feature_enabled?(:campaigns_api)
  end

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.autofix_generation_enabled?(entity)
    SecurityCampaigns.enabled?(entity) && !entity.feature_enabled?(:security_campaigns_disable_autofix_generation)
  end

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.autofix_pr_creation_enabled?(entity)
    SecurityCampaigns.enabled?(entity) && entity.feature_enabled?(:security_campaigns_autofix_pr_creation)
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def self.show_onboarding_message?(current_user)
    !current_user.dismissed_notice?(ONBOARDING_DISMISSAL_NOTICE_NAME)
  end

  sig { params(org: Organization).returns(T::Enumerable[User]) }
  def self.potential_campaign_managers(org:)
    org.admins + SecurityProduct::SecurityManagers.new(org).users
  end

  sig { params(entity: T.any(User, Organization)).returns(T.nilable(String)) }
  def self.about_docs_url(entity)
    DocsUrlConfig.url_for("code-security/about-security-campaigns")
  end

  sig { params(entity: T.any(User, Organization)).returns(T.nilable(String)) }
  def self.closing_or_deleting_docs_url(entity)
    DocsUrlConfig.url_for("code-security/creating-tracking-security-campaigns-closing-or-deleting-security-campaigns")
  end

  sig { params(entity: T.any(User, Organization)).returns(T.nilable(String)) }
  def self.best_practice_docs_url(entity)
    DocsUrlConfig.url_for("code-security/best-practice-fix-alerts-at-scale-selecting-security-alerts-for-remediation")
  end

  sig { params(entity: T.any(User, Organization)).returns(T.nilable(String)) }
  def self.fixing_alerts_docs_url(entity)
    DocsUrlConfig.url_for("code-security/fixing-alerts-in-security-campaign")
  end

  sig { params(entity: T.any(User, Organization)).returns(Integer) }
  def self.max_alerts_repository_count(entity)
    entity.feature_enabled?(:security_campaigns_increased_max_alerts_repository_count) ? 1000 : 100
  end
end
