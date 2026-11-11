# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrganizationBanners
      class CodeSecurityRiskAssessmentBannerComponent < OrganizationIpmBannerBaseComponent
        include ApplicationComponent::Rescuable

        NUDGE_ID = :secure_ipm_security_risk_assessment_v2
        NUDGE_CATEGORY = "secure_ipm_security_risk_assessment_v2"
        NUDGE_GROUP_VALUE = :engage
        FEATURE_FLAG = :secure_ipm_security_risk_assessment_v2

        rescue_from StandardError, with: :nothing

        private

        sig { override.returns(T::Boolean) }
        def eligible_for_nudge?
          return false unless base_eligibility_checks_satisfied?

          return false unless can_access_secret_risk_assessments?

          assessment_window_open?
        end

        # The nudge promotes "scan for both secrets and vulnerabilities", so we keep showing it
        # while the org can still run a new assessment of EITHER type. The cheaper, network-free
        # Code Security signal is checked first so we can short-circuit before making the Secret
        # Protection service call.
        sig { returns(T::Boolean) }
        def assessment_window_open?
          code_security_window_open? || secret_protection_window_open?
        end

        # Code Security (CSRA): `latest_results_for_org` returns nil when the org has never run an
        # assessment (window open). Otherwise the payload's `can_request_another_assessment` reflects
        # the local COOLDOWN_DAYS cooldown plus the failed / all-timed-out retry cases.
        sig { returns(T::Boolean) }
        memoize def code_security_window_open?
          results = ::SecurityProductsEnablement::CodeScanningAssessment.latest_results_for_org(organization)
          return true if results.nil?

          results.can_request_another_assessment
        end

        # Secret Protection (SRA): the service owns the cadence. A nil assessment means the org has
        # never run one (404) or the service errored; in both cases we keep the existing fail-open
        # behavior and treat the window as open. Otherwise use the service's
        # `can_request_another_assessment`. `next_request_available_at` is deliberately not used as a
        # window signal because it is coerced to the current time whenever the window is open.
        sig { returns(T::Boolean) }
        memoize def secret_protection_window_open?
          assessment, _error = ::SecretScanning::Services::SecretRiskAssessmentsService.get_latest_assessment_for_org(organization, T.must(user))
          return true if assessment.nil?

          assessment.can_request_another_assessment
        end

        sig { override.returns(String) }
        def nudge_category
          NUDGE_CATEGORY
        end

        sig { override.returns(Symbol) }
        def nudge_id
          NUDGE_ID
        end

        sig { override.returns(Symbol) }
        def nudge_group
          NUDGE_GROUP_VALUE
        end

        sig { override.returns(Symbol) }
        def feature_flag
          FEATURE_FLAG
        end

        sig { override.returns(T.nilable(T::Hash[Symbol, String])) }
        def nudge_label
          { text: "New" }
        end

        sig { override.returns(String) }
        def nudge_title
          "Now scan for both secrets and vulnerabilities"
        end

        sig { override.returns(String) }
        def nudge_description
          "Scan your organization for free with code scanning and get an audit of vulnerabilities and their severity levels, rule types, and language breakdown."
        end

        sig { override.returns(String) }
        def primary_cta_text
          "Scan now"
        end

        sig { override.returns(String) }
        def primary_cta_action = "click"

        sig { override.returns(T::Boolean) }
        def show_secondary_cta? = true

        sig { override.returns(String) }
        def secondary_cta_post_path
          helpers.organization_dismiss_notice_path(
            notice: (nudge_id.to_s + "_remind_me_later_cta").to_sym,
            organization_id: organization.id
          )
        end

        sig { override.returns(String) }
        def secondary_cta_post_behavior
          "dismiss"
        end

        sig { override.returns(T.nilable(T::Hash[Symbol, String])) }
        def secondary_action_flash
          {
            title: "Reminder set for 7 days.",
            description: "Reminder set for 7 days. Start a risk assessment anytime.",
            linkText: "risk assessment",
            linkHref: "/orgs/#{organization.display_login}/security/assessments",
            linkAnalyticsAction: "remind_me_later_flash_link",
          }
        end

        sig { override.returns(String) }
        def nudge_image_path_dark = "/static/images/in-product-messaging/risk-assessment-dark-bg.png"

        sig { override.returns(String) }
        def nudge_image_path_light = "/static/images/in-product-messaging/risk-assessment-light-bg.png"

        sig { override.returns(String) }
        def nudge_image_alt_dark = "Secret scanning dashboard preview"

        sig { override.returns(String) }
        def nudge_image_alt_light = "Secret scanning dashboard preview"

        sig { override.returns(String) }
        def dismiss_path
          helpers.growth_notice_dismissals_path(
            notice: nudge_id.to_s,
            organization_id: organization.id
          )
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def additional_analytics
          {
            plan: plan&.name,
          }
        end

        sig { returns(T::Boolean) }
        def base_eligibility_checks_satisfied?
          return false unless organization.feature_flag_enabled?(feature_flag, default: false)

          is_dismissed = Growth::NoticeDismissal.new(T.must(user)).dismissed_organization_notice?(
            nudge_id.to_s,
            organization_id: organization.id
          )
          return false if is_dismissed

          return false if T.must(user).interacted_with_a_nudge(
            id: (nudge_id.to_s + "_remind_me_later_cta").to_sym,
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
          return false unless SecurityProducts::AccessControl::RiskAssessments.new(organization).risk_assessment_available?
          return false unless SecurityProducts::AccessControl::RiskAssessments.new(organization).has_access_to_risk_assessments?(current_user)
          return false unless organization.advanced_security_purchased?

          # For GitHub Team plan orgs, show to all org admins who don't have Security Center access
          if plan&.business?
            return organization.admin_ids.include?(current_user.id)
          end

          # For GitHub Enterprise Cloud orgs, show only to enterprise account owners
          if plan&.business_plus?
            return false if business.nil?
            return business&.owner?(current_user)
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
