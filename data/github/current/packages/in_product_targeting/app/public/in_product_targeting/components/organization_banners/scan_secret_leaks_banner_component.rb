# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrganizationBanners
      class ScanSecretLeaksBannerComponent < OrganizationIpmBannerBaseComponent
        include ApplicationComponent::Rescuable

        NUDGE_ID = :secret_scanning_first_scan_nudge
        NUDGE_GROUP_VALUE = :engage

        rescue_from StandardError, with: :nothing

        private

        sig { override.returns(T::Boolean) }
        def eligible_for_banner?
          return false unless base_eligibility_checks_satisfied?
          return false unless can_access_secret_risk_assessments?

          assessment, error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(organization, T.must(user))
          return false if !error && assessment

          true
        end

        sig { override.returns(String) }
        def nudge_category
          ghec_organization? ? "secret_scanning_first_scan_nudge_ghec_1" : "secret_scanning_first_scan_nudge_1"
        end

        sig { override.returns(Symbol) }
        def nudge_id = NUDGE_ID

        sig { override.returns(Symbol) }
        def nudge_group = NUDGE_GROUP_VALUE

        sig { override.returns(String) }
        def banner_label = "New"

        sig { override.returns(String) }
        def banner_title = "Scan for secret leaks with GitHub"

        sig { override.returns(String) }
        def banner_description
          "Run a free secret risk assessment to determine if you have any exposed secrets in your organization's repositories."
        end

        sig { override.returns(String) }
        def primary_cta_text = "Scan now"

        sig { override.returns(String) }
        def primary_cta_href
          helpers.security_center_assessments_path(organization)
        end

        sig { override.returns(String) }
        def primary_cta_action = "click"

        sig { override.returns(T::Boolean) }
        def show_secondary_cta? = true

        sig { override.returns(String) }
        def secondary_cta_text = "Remind me later"

        sig { override.returns(String) }
        def secondary_cta_href
          helpers.organization_dismiss_notice_path(
            notice: :free_health_assessment_nudge_remind_me_later_cta,
            organization_id: organization.id
          )
        end

        sig { override.returns(String) }
        def secondary_cta_action = "remind_later"

        sig { override.returns(String) }
        def dismiss_path
          helpers.growth_notice_dismissals_path(notice: "free_health_assessment_nudge", organization_id: organization.id)
        end

        sig { override.returns(String) }
        def banner_image_path_dark = "secret-scanning/scan-secret-leaks-banner-dark.png"

        sig { override.returns(String) }
        def banner_image_path_light = "secret-scanning/scan-secret-leaks-banner-light.png"

        sig { override.returns(String) }
        def banner_image_alt_dark = "Secret scanning dashboard preview"

        sig { override.returns(String) }
        def banner_image_alt_light = "Secret scanning dashboard preview"

        # Private helper methods
        sig { returns(T::Boolean) }
        def ghec_organization?
          organization.plan.business_plus?
        end

        sig { returns(T::Boolean) }
        def base_eligibility_checks_satisfied?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || T.must(user).is_enterprise_managed?
          return false unless T.must(user).feature_flag_enabled?(:free_health_assessment_nudge, default: false)
          return false unless organization.feature_flag_enabled?(:free_health_assessment_nudge, default: false)

          is_dismissed = Growth::NoticeDismissal.new(T.must(user)).dismissed_organization_notice?(
            "free_health_assessment_nudge",
            organization_id: organization.id
          )
          return false if is_dismissed

          return false if T.must(user).interacted_with_a_nudge(
            id: :free_health_assessment_nudge_remind_me_later_cta,
            org_id: organization.id,
            after: 7.days.ago,
            type: :dismissal
          )

          has_qualifying_repo = organization.repositories
            .where("created_at <= ?", Time.current - 30.days)
            .limit(1)
            .present?

          has_qualifying_repo
        end

        sig { returns(T::Boolean) }
        def can_access_secret_risk_assessments?
          current_user = T.must(user)
          return false unless organization.direct_or_team_member?(current_user)
          return false unless SecretScanning::Features::Org::TokenScanning.new(organization).secret_risk_assessment_available?
          return false unless SecurityProducts::AccessControl::RiskAssessments.new(organization).has_access_to_risk_assessments?(current_user)
          return false unless organization.advanced_security_purchased?

          # For GitHub Team plan orgs, show to all org admins who don't have Security Center access
          if organization.plan.business?
            return false if can_access_security_center?
            return organization.admin_ids.include?(current_user.id)
          end

          # For GitHub Enterprise Cloud orgs, show only to enterprise account owners
          if organization.plan.business_plus?
            business = organization.business
            return false if business.nil?
            return business.owner?(current_user)
          end

          false
        end

        sig { returns(T::Boolean) }
        def can_access_security_center?
          current_user = T.must(user)
          !!(organization.direct_or_team_member?(current_user) && SecurityCenter::SecurityFeatures.security_center_available?(organization))
        end
      end
    end
  end
end
