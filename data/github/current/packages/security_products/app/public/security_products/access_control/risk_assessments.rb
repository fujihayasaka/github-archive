# typed: strict
# frozen_string_literal: true

module SecurityProducts::AccessControl
  # Unified access control for both Secret Protection and Code Security risk assessments.
  class RiskAssessments
    sig { params(organization: Organization).void }
    def initialize(organization)
      @organization = organization
    end

    sig { params(user: User).returns(T::Boolean) }
    def has_access_to_risk_assessments?(user)
      can_manage_security_products = SecurityProduct::Permissions::OrgAuthz.new(@organization, actor: user).can_manage_org_security_products?
      @organization.adminable_by?(user) || can_manage_security_products
    end

    sig { returns(T::Boolean) }
    def risk_assessment_available?
      # all orgs that belong to a business can run an assessment
      # all orgs on a Teams plan can run an assessment
      @organization.business.present? || @organization.plan.business?
    end
  end
end
