# typed: true
# frozen_string_literal: true

module SecurityCenter
  class NavComponent < ApplicationComponent
    include GitHub::Memoizer

    module TabNames
      RISK = "Risk"
      COVERAGE = "Coverage"
      OVERVIEW_DASHBOARD = "Overview"
      TRENDS_ENABLEMENT = "Enablement trends"
      TRENDS_CODE_SCANNING = "CodeQL pull request alerts"
      TRENDS_SECRET_SCANNING = "Secret scanning"
      SECRET_SCANNING = "Secret scanning"
      CODE_SCANNING = "Code scanning"
      DEPENDABOT = "Dependabot"
      SECRET_SCANNING_BYPASS_REQUESTS = "Push protection bypass"
      SECRET_SCANNING_DEFAULT = "Default"
      SECRET_SCANNING_EXPERIMENTAL = "Experimental"
    end

    SECRET_SCANNING_DEFAULT = "secret_scanning_default" # used for split tab labelling only
    SECRET_SCANNING_EXPERIMENTAL = "secret_scanning_experimental" # used for split tab labelling only

    SECURITY_FEATURE_TABS_ORDER = [
      ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
      ::SecurityCenter::SecurityFeatures::CODE_SCANNING,
      ::SecurityCenter::SecurityFeatures::SECRET_SCANNING,
    ]

    SECURITY_FEATURE_TAB_SPLITS = {
      ::SecurityCenter::SecurityFeatures::SECRET_SCANNING => [
        SECRET_SCANNING_DEFAULT,
        SECRET_SCANNING_EXPERIMENTAL,
      ]
    }

    NAV_TAB_IDS = [
      :risk,
      :coverage,
      :overview_dashboard,
      :adoption_report,
      :code_scanning_metrics,
      :secret_scanning_metrics,
      :dependabot_alerts,
      :code_scanning,
      :secret_scanning,
      :organization_secret_scanning_bypass_requests,
      :secret_scanning_default,
      :secret_scanning_experimental,
    ]

    TRENDS_TAB_GROUP_TEST_SELECTOR = "trends-section-test-selector"
    BYPASS_REQUESTS_GROUP_TEST_SELECTOR = "bypass-requests-section-test-selector"

    def initialize(
      selected_tab:,
      organization:
    )
      raise ArgumentError, "Invalid selected_tab: #{selected_tab}" unless SecurityCenter::NavComponent::NAV_TAB_IDS.include?(selected_tab) || selected_tab.to_s.start_with?("security_campaign_")

      @selected_tab = selected_tab
      @organization = organization

      @visible_features = SecurityFeatures.visible_features(@organization)
      @token_scanning = SecretScanning::Features::Org::TokenScanning.new(@organization)
      @secret_scanning_delegated_bypass = SecretScanning::Features::Org::DelegatedBypass.new(@organization)
    end

    private

    memoize def render_security_campaigns?
      SecurityCampaigns.enabled?(@organization) &&
        (can_manage_security_products? || security_campaigns_organization_access?)
    end

    memoize def security_campaigns_organization_access?
      @organization.direct_or_team_member?(current_user)
    end

    # An unfiltered list of all open security campaigns in the org.
    # See `security_campaigns` for the set of campaigns visible to the current user.
    memoize def open_security_campaigns
      SecurityCampaigns::SecurityCampaign.open.where(organization: @organization).order(created_at: :asc).to_a
    end

    memoize def security_campaigns
      open_security_campaigns.filter do |campaign|
        next true if can_manage_security_products?
        next false unless security_campaigns_organization_access?

        # only return the campaigns where the user has access to at least one repository, otherwise
        # they will just see an empty campaign
        # there is currently a maximum of 10 campaigns and each can have up to 100 repositories
        # if this is increased then we will need to rework this check to be more efficient
        @organization.repositories.active.where(id: campaign.security_campaign_alerts.distinct.pluck(:repository_id)).any? do |repository|
          repository.code_scanning_readable_by?(current_user)
        end
      end
    end

    memoize def render_closed_campaigns?
      closed_campaigns_count.positive?
    end

    memoize def closed_campaigns_count
      SecurityCampaigns::SecurityCampaign.closed.where(organization: @organization).count
    end

    memoize def campaigns_creation_enabled?
      SecurityCampaigns.enabled?(@organization) && can_manage_security_products?
    end

    memoize def campaigns_limit_reached?
      open_security_campaigns.length >= SecurityCampaigns::MAX_CAMPAIGNS_COUNT
    end

    def create_campaigns_buttons_label
      return SecurityCampaigns::MAX_CAMPAIGNS_CREATION_ERROR_MESSAGE if campaigns_limit_reached?
      "New campaign"
    end

    def render_code_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::CODE_SCANNING)
    end

    def render_secret_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::SECRET_SCANNING)
    end

    def render_secret_scanning_delegated_bypass?
      @secret_scanning_delegated_bypass.can_view_requests_list?(current_user)
    end

    def render_feature_tab?(feature_type)
      case feature_type
      when SecurityFeatures::SECRET_SCANNING
        # Secret scanning have their own enablement check
        @token_scanning.feature_available?
      else
        @visible_features.include?(feature_type)
      end
    end

    def split_feature_tab?(feature_type)
      case feature_type
      when SecurityFeatures::SECRET_SCANNING
        # Secret scanning has its own enablement check
        @token_scanning.feature_available? && SecurityCenter::FeatureFlagHelper.split_secret_scanning_tab_counts?(current_user, @organization)
      else
        false
      end
    end

    def render_any_feature_tab?
      SecurityCenter::NavComponent::SECURITY_FEATURE_TABS_ORDER.any? do |feature_type|
        render_feature_tab?(feature_type)
      end
    end

    memoize def can_manage_security_products?
      SecurityProduct::Permissions::OrgAuthz.new(@organization, actor: current_user).can_manage_security_products?
    end

    def get_nav_tab_name(feature_type)
      return TabNames::SECRET_SCANNING if feature_type == ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
      return TabNames::SECRET_SCANNING_DEFAULT if feature_type == SECRET_SCANNING_DEFAULT
      return TabNames::SECRET_SCANNING_EXPERIMENTAL if feature_type == SECRET_SCANNING_EXPERIMENTAL
      return TabNames::CODE_SCANNING if feature_type == ::SecurityCenter::SecurityFeatures::CODE_SCANNING
      return TabNames::DEPENDABOT if feature_type == ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS

      raise ArgumentError, "Unrecognized feature_type: #{feature_type}"
    end

    def get_nav_tab_icon(feature_type)
      return :key if feature_type == ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
      return :codescan if feature_type == ::SecurityCenter::SecurityFeatures::CODE_SCANNING
      return :dependabot if feature_type == ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS

      raise ArgumentError, "Unrecognized feature_type: #{feature_type}"
    end

    def get_nav_tab_path(feature_type)
      return security_center_alerts_secret_scanning_path(org: @organization) if feature_type == ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
      return security_center_alerts_secret_scanning_path(org: @organization) if feature_type == SECRET_SCANNING_DEFAULT
      return security_center_alerts_secret_scanning_path(org: @organization, query: "is:open #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}") if feature_type == SECRET_SCANNING_EXPERIMENTAL
      return security_center_alerts_code_scanning_path(org: @organization) if feature_type == ::SecurityCenter::SecurityFeatures::CODE_SCANNING
      return security_center_alerts_dependabot_path(org: @organization) if feature_type == ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS

      raise ArgumentError, "Unrecognized feature_type: #{feature_type}"
    end
  end
end
