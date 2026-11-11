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
      organization.direct_or_team_member?(user) &&
        !can_access_security_center?(user, organization) && # Only nudge users who haven't yet gotten access to the Security Center
        SecretScanning::Features::Org::TokenScanning.new(organization).secret_risk_assessment_available? &&
        SecretScanning::AccessControl::SecretRiskAssessments.new(organization).has_access_to_secret_risk_assessments?(user) &&
        (organization.plan.business? || organization.plan.business_plus?) && # Only nudge users who are in Team or GHEC orgs
        organization.advanced_security_purchased?
    end

  end
end
