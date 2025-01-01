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
      TRENDS_ENABLEMENT = "Enablement trends"
      TRENDS_DEPENDABOT = "Dependabot dashboard"
      TRENDS_CODE_SCANNING = "CodeQL pull request insights"
      TRENDS_SECRET_SCANNING = "Secret scanning insights"
      SECRET_SCANNING = "Secret scanning"
      CODE_SCANNING = "Code scanning"
      CODE_SCANNING_ALERT_DISMISSAL_REQUESTS = "Code scanning alert dismissal"
      DEPENDABOT = "Dependabot"
      SECRET_RISK_ASSESSMENT = "Assessments"
      SECRET_SCANNING_BYPASS_REQUESTS = "Push protection bypass"
      SECRET_SCANNING_CLOSURE_REQUESTS = "Secret scanning alert dismissal"
      SECRET_SCANNING_DEFAULT = "Default"
      SECRET_SCANNING_GENERIC = "Generic"
    end

    SECRET_SCANNING_DEFAULT = "secret_scanning_default" # used for split tab labelling only
    SECRET_SCANNING_GENERIC = "secret_scanning_generic" # used for split tab labelling only

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
      :secret_scanning_metrics,
      :dependabot_alerts,
      :code_scanning,
      :secret_scanning,
      :organization_secret_scanning_bypass_requests,
      :organization_secret_scanning_closure_requests,
      :secret_scanning_default,
      :secret_scanning_generic,
      :organization_code_scanning_alert_dismissal_requests,
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

    # An unfiltered list of all open security campaigns in the org.
    # See `security_campaigns` for the set of campaigns visible to the current user.
    memoize def open_security_campaigns
      SecurityCampaigns::SecurityCampaign.open.where(organization: @organization).order(created_at: :asc).to_a
    end

    memoize def security_campaigns
      return open_security_campaigns if can_manage_security_products?
      return [] unless security_campaigns_organization_access?

      allowed_repository_ids = @auth_enumerator.allowed_repository_ids_by_feature_for_organization_member[SecurityCenter::SecurityFeatures::CODE_SCANNING]&.first

      query_service = CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session: nil,
        organization: T.must(@organization),
        security_campaign_ids: open_security_campaigns.map(&:id),
        allowed_repository_ids:
      )
      SecurityCampaigns::CampaignWithCounts.load(
        security_campaigns: open_security_campaigns, query_service:
      ).filter do |campaign_with_counts|
        # filter out campaign with 0 counts
        campaign_with_counts.total_count.positive?
      end.map(&:security_campaign)
    end

    memoize def closed_campaigns_count
      SecurityCampaigns::SecurityCampaign.closed.where(organization: @organization).count
    end

    memoize def campaigns_limit_reached?
      open_security_campaigns.length >= SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT
    end

    def create_campaigns_buttons_label
      return SecurityCampaigns::MAX_OPEN_CAMPAIGNS_CREATION_ERROR_MESSAGE if campaigns_limit_reached?
      "New campaign"
    end

    def render_code_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::CODE_SCANNING)
    end

    def render_secret_risk_assessment_tab?
      return false unless ::SecretScanning::Features::Org::TokenScanning.new(@organization).secret_risk_assessment_available?
      ::SecretScanning::AccessControl::SecretRiskAssessments.new(@organization).has_access_to_secret_risk_assessments?(current_user)
    end

    def render_secret_scanning_metrics_tab?
      render_feature_tab?(SecurityFeatures::SECRET_SCANNING)
    end

    def render_secret_scanning_delegated_bypass?
      @secret_scanning_delegated_bypass.can_view_requests_list?(current_user)
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

    def render_requests?
      render_secret_scanning_delegated_bypass? || render_secret_scanning_delegated_closures? || render_code_scanning_alert_dismissal?
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

      raise ArgumentError, "Unrecognized feature_type: #{feature_type}"
    end
  end
end
