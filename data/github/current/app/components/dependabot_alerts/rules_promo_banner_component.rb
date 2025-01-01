# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class RulesPromoBannerComponent < ApplicationComponent
    ORG_RULES_FEATURE_FLAG = "dependabot_alert_org_rules"

    sig { returns(Organization) }
    attr_reader :org

    sig { returns(Repository) }
    attr_reader :repository

    def initialize(repository: nil, organization: nil)
      @repository = repository
      @organization = organization
    end

    def render?
      # don't show the banner if the user has already dismissed it
      return false if current_user.dismissed_notice?(UserNotice::DEPENDABOT_ALERTS_RULES_BANNER_NOTICE)

      if @repository
        @repository.owner.feature_enabled?(ORG_RULES_FEATURE_FLAG.to_sym)
      elsif @organization
        @organization.feature_enabled?(ORG_RULES_FEATURE_FLAG.to_sym)
      end
    end

    def ghas_docs_link
      helpers.docs_url("get-started/about-github-advanced-security")
    end

    def dependabot_rules_link
      "#{GitHub.help_url}/code-security/dependabot/dependabot-alert-rules/about-dependabot-alert-rules"
    end
  end
end
