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
    end

    SECURITY_FEATURE_TABS_ORDER = [
      ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
      ::SecurityCenter::SecurityFeatures::CODE_SCANNING,
      ::SecurityCenter::SecurityFeatures::SECRET_SCANNING,
    ]

    NAV_TAB_IDS = [
      :risk,
      :coverage,
      :overview_dashboard,
      :adoption_report,
      :code_scanning_metrics,
      :secret_scanning_metrics,
      :unified_alerts,
      :dependabot_alerts,
      :code_scanning,
      :secret_scanning,
    ]

    TRENDS_TAB_GROUP_TEST_SELECTOR = "trends-section-test-selector"

    def initialize(
      selected_tab:,
      organization:
    )
      raise ArgumentError, "Invalid selected_tab: #{selected_tab}" unless SecurityCenter::NavComponent::NAV_TAB_IDS.include?(selected_tab) || selected_tab.to_s.start_with?("security_campaign_")

      @selected_tab = selected_tab
      @organization = organization

      @visible_features = SecurityFeatures.visible_features(@organization)
      @token_scanning = SecretScanning::Features::Org::TokenScanning.new(@organization)
    end

    private

    memoize def render_security_campaigns?
      SecurityCampaigns.enabled?(@organization) && can_manage_security_products? &&
      (security_campaigns.any? || render_closed_campaigns?)
    end

    memoize def security_campaigns
      SecurityCampaigns::SecurityCampaign.open.where(organization: @organization).order(created_at: :asc).to_a
    end

    memoize def render_closed_campaigns?
      GitHub.flipper[:security_campaigns_closed].enabled?(current_user) && closed_campaigns_count.positive?
    end

    memoize def closed_campaigns_count
      SecurityCampaigns::SecurityCampaign.closed.where(organization: @organization).count
    end

    def render_code_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::CODE_SCANNING)
    end

    def render_secret_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::SECRET_SCANNING)
    end

    memoize def render_unified_alerts?
      SecurityCenter::FeatureFlagHelper.show_unified_alerts?(current_user, @organization) &&
        render_any_feature_tab? && can_manage_security_products?
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
      return security_center_alerts_code_scanning_path(org: @organization) if feature_type == ::SecurityCenter::SecurityFeatures::CODE_SCANNING
      return security_center_alerts_dependabot_path(org: @organization) if feature_type == ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS

      raise ArgumentError, "Unrecognized feature_type: #{feature_type}"
    end
  end
end
