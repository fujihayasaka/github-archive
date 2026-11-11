# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module ScanSecretLeaksConcern
    extend ActiveSupport::Concern

    include HawaiiExperimentHelper

    sig { params(user: User).returns(Integer) }
    def get_scan_secret_conversion_modal_variant(user)
      initial_variant = hawaii_experiment_variant(
        experiment_id: "secret_protection_conversion_modal",
        user_id: user.id,
        variant_count: 2,
      )

      # Override variant based on feature flags
      variant = initial_variant
      variant = 0 if user.feature_flag_enabled?(:force_enable_secret_protection_all_repos_modal_nudge_0, default: false)
      variant = 1 if user.feature_flag_enabled?(:force_enable_secret_protection_all_repos_modal_nudge_1, default: false)

      variant
    end

    sig { params(user: T.nilable(User), organization: T.nilable(Organization)).returns(T::Boolean) }
    def show_scan_secret_leaks_promo?(user, organization)
      return false unless user
      return false unless organization
      return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || user.is_enterprise_managed?
      return false unless user.feature_flag_enabled?(:free_health_assessment_nudge, default: false) && organization.feature_flag_enabled?(:free_health_assessment_nudge, default: false)

      is_dismissed = Growth::NoticeDismissal.new(user).dismissed_organization_notice?("free_health_assessment_nudge", organization_id: organization.id)
      return false if is_dismissed

      return false if user.interacted_with_a_nudge(
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

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def can_access_security_center?(user, organization)
      !!(organization.direct_or_team_member?(user) && SecurityCenter::SecurityFeatures.security_center_available?(organization))
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def can_access_secret_risk_assessments?(user, organization)
      return false unless organization.direct_or_team_member?(user)
      return false unless SecretScanning::Features::Org::TokenScanning.new(organization).secret_risk_assessment_available?
      return false unless SecurityProducts::AccessControl::RiskAssessments.new(organization).has_access_to_risk_assessments?(user)
      return false unless organization.advanced_security_purchased?

      # For GitHub Team plan orgs, show to all org admins who don't have Security Center access
      if organization.plan.business?
        return false if can_access_security_center?(user, organization)
        return organization.admin_ids.include?(user.id)
      end

      # For GitHub Enterprise Cloud orgs, show only to enterprise account owners
      if organization.plan.business_plus?
        business = organization.business
        return false if business.nil?
        return business.owner?(user)
      end

      false
    end
  end
end
