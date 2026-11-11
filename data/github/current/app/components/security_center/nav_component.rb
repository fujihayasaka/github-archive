# typed: true
# frozen_string_literal: true

module SecurityCenter
  class NavComponent < ApplicationComponent
    include GitHub::Memoizer

    module TabNames
      RISK = "Risk"
      COVERAGE = "Coverage"
      OVERVIEW_DASHBOARD = "Overview"
      CAMPAIGNS = "Campaigns"
      TRENDS_ENABLEMENT = "Enablement"
      TRENDS_DEPENDABOT = "Dependabot"
      TRENDS_CODE_SCANNING = "CodeQL pull requests"
      TRENDS_SECRET_SCANNING = "Secret scanning"
      SECRET_SCANNING = "Secret scanning"
      CODE_QUALITY = "Code quality"
      CODE_SCANNING = "Code scanning"
      CODE_SCANNING_ALERT_DISMISSAL_REQUESTS = "Code scanning"
      DEPENDABOT = "Dependabot"
      DEPENDABOT_MALWARE = "Malware"
      DEPENDABOT_VULNERABILITIES = "Vulnerabilities"
      DEPENDABOT_ALERT_DISMISSAL_REQUESTS = "Dependabot"
      SECRET_RISK_ASSESSMENT = "Assessments"
      SECRET_SCANNING_BYPASS_REQUESTS = "Push protection bypass"
      SECRET_SCANNING_CLOSURE_REQUESTS = "Secret scanning"
      SECRET_SCANNING_DEFAULT = "Default"
      SECRET_SCANNING_GENERIC = "Generic"
      LICENSE_COMPLIANCE_BYPASS_REQUESTS = "Licenses"
    end

    SECRET_SCANNING_DEFAULT = "secret_scanning_default" # used for split tab labelling only
    SECRET_SCANNING_GENERIC = "secret_scanning_generic" # used for split tab labelling only

    DEPENDABOT_MALWARE = "dependabot_malware" # used for split tab labelling only
    DEPENDABOT_VULNERABILITIES = "dependabot_vulnerabilities" # used for split tab labelling only

    SECURITY_FEATURE_TABS_ORDER = [
      ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
      ::SecurityCenter::SecurityFeatures::CODE_SCANNING,
      ::SecurityCenter::SecurityFeatures::SECRET_SCANNING,
    ]

    SECURITY_FEATURE_TAB_SPLITS = {
      ::SecurityCenter::SecurityFeatures::SECRET_SCANNING => [
        SECRET_SCANNING_DEFAULT,
        SECRET_SCANNING_GENERIC,
      ]
    }

    NAV_TAB_IDS = [
      :risk,
      :coverage,
      :overview_dashboard,
      :campaigns,
      :adoption_report,
      :dependabot_metrics,
      :code_scanning_metrics,
      :secret_risk_assessment,
      :risk_assessments,
      :secret_scanning_metrics,
      :dependabot_alerts,
      :code_quality,
      :code_scanning,
      :secret_scanning,
      :organization_secret_scanning_bypass_requests,
      :organization_secret_scanning_closure_requests,
      :organization_license_compliance_bypass_requests,
      :secret_scanning_default,
      :secret_scanning_generic,
      :dependabot_malware,
      :dependabot_vulnerabilities,
      :organization_code_scanning_alert_dismissal_requests,
      :organization_dependabot_alert_dismissal_requests,
    ]

    TRENDS_TAB_GROUP_TEST_SELECTOR = "trends-section-test-selector"
    BYPASS_REQUESTS_GROUP_TEST_SELECTOR = "bypass-requests-section-test-selector"

    def initialize(
      selected_tab:,
      organization:,
      auth_enumerator: nil
    )
      raise ArgumentError, "Invalid selected_tab: #{selected_tab}" unless SecurityCenter::NavComponent::NAV_TAB_IDS.include?(selected_tab) || selected_tab.to_s.start_with?("security_campaign_")

      @selected_tab = selected_tab
      @organization = organization
      @auth_enumerator = auth_enumerator

      @visible_features = SecurityFeatures.visible_features(@organization)
      @token_scanning = SecretScanning::Features::Org::TokenScanning.new(@organization)
      @secret_scanning_delegated_bypass = SecretScanning::Features::Org::DelegatedBypass.new(@organization)
      @secret_scanning_delegated_closures = SecretScanning::Features::Org::DelegatedClosures.new(@organization)
      @dependabot_delegated_dismissals = Dependabot::SecurityProduct::DelegatedClosures.new(@organization)
    end

    private

    memoize def team_org_has_never_enabled_security_sku?
      eligibility = ::Repository::SecurityCenterBusinessPlanOrgEligibility.new
      eligibility.eligible_owner?(@organization) && !eligibility.enabled?(@organization)
    end

    memoize def render_security_campaigns_tab?
      SecurityCampaigns.enabled?(@organization) &&
      (can_manage_security_products? || security_campaigns_organization_access?)
    end

    memoize def security_campaigns_organization_access?
      @organization.direct_or_team_member?(current_user)
    end

    def render_code_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::CODE_SCANNING)
    end

    def render_secret_risk_assessment_tab?
      risk_assessments = ::SecurityProducts::AccessControl::RiskAssessments.new(@organization)
      return false unless risk_assessments.risk_assessment_available?
      risk_assessments.has_access_to_risk_assessments?(current_user)
    end

    def render_secret_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::SECRET_SCANNING)
    end

    def render_secret_scanning_delegated_bypass?
      @secret_scanning_delegated_bypass.can_view_requests_list?(current_user)
    end

    def render_license_compliance_delegated_bypass?
      Permissions::LicensePolicy.can_view_organization_license_compliance_alerts?(current_user, @organization)
    end

    def render_dependabot_metrics_tab?
      # Page will not render unless the user can veiw Dependabot alerts, even if navigated to by URL.
      render_feature_tab?(SecurityFeatures::DEPENDABOT_ALERTS)
    end

    def render_secret_scanning_delegated_closures?
      @secret_scanning_delegated_closures.user_can_review_closure_requests?(current_user)
    end

    def render_code_scanning_alert_dismissal?
      CodeScanning::AlertDismissalService.can_view_org_requests?(org: @organization, user: current_user)
    end

    memoize def render_dependabot_alert_dismissal?
      @dependabot_delegated_dismissals.user_can_view_closure_requests?(current_user)
    end

    def render_code_quality_tab?
      CodeQuality.available?(@organization)
    end

    def render_requests?
      render_secret_scanning_delegated_bypass? || render_secret_scanning_delegated_closures? || render_code_scanning_alert_dismissal? || render_dependabot_alert_dismissal? || render_license_compliance_delegated_bypass?
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
        @token_scanning.feature_available?
      when SecurityFeatures::DEPENDABOT_ALERTS
        true
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
      SecurityProduct::Permissions::OrgAuthz.new(@organization, actor: current_user).can_manage_org_security_products?
    end

    def get_nav_tab_name(feature_type)
      return TabNames::SECRET_SCANNING if feature_type == ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
      return TabNames::SECRET_SCANNING_DEFAULT if feature_type == SECRET_SCANNING_DEFAULT
      return TabNames::SECRET_SCANNING_GENERIC if feature_type == SECRET_SCANNING_GENERIC
      return TabNames::CODE_SCANNING if feature_type == ::SecurityCenter::SecurityFeatures::CODE_SCANNING
      return TabNames::DEPENDABOT if feature_type == ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS
      return TabNames::DEPENDABOT_MALWARE if feature_type == DEPENDABOT_MALWARE
      return TabNames::DEPENDABOT_VULNERABILITIES if feature_type == DEPENDABOT_VULNERABILITIES

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
      return security_center_alerts_secret_scanning_path(org: @organization, query: "is:open #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::GENERIC_RESULTS}") if feature_type == SECRET_SCANNING_GENERIC
      return security_center_alerts_code_scanning_path(org: @organization) if feature_type == ::SecurityCenter::SecurityFeatures::CODE_SCANNING
      return security_center_alerts_dependabot_path(org: @organization) if feature_type == ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS
      return security_center_alerts_dependabot_malware_path(org: @organization) if feature_type == DEPENDABOT_MALWARE
      return security_center_alerts_dependabot_path(org: @organization) if feature_type == DEPENDABOT_VULNERABILITIES

      raise ArgumentError, "Unrecognized feature_type: #{feature_type}"
    end

    sig { returns String }
    memoize def security_and_quality_navigation_title
      CodeQuality.combined_security_and_quality_title
    end

    def get_split_tabs(feature_type)
      case feature_type
      when SecurityFeatures::SECRET_SCANNING
        SECURITY_FEATURE_TAB_SPLITS[feature_type]
      when SecurityFeatures::DEPENDABOT_ALERTS
        dependabot_split_tabs
      else
        []
      end
    end

    def dependabot_split_tabs
      [DEPENDABOT_MALWARE, DEPENDABOT_VULNERABILITIES]
    end
  end
end
