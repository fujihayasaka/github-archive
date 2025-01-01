# typed: strict
# frozen_string_literal: true

module SecretScanning::AccessControl
  class SecretRiskAssessments
    sig { params(organization: Organization).void }
    def initialize(organization)
      @organization = organization
    end

    sig { params(user: User).returns(T::Boolean) }
    def has_access_to_secret_risk_assessments?(user)
      can_manage_security_products = SecurityProduct::Permissions::OrgAuthz.new(@organization, actor: user).can_manage_security_products?
      @organization.adminable_by?(user) || can_manage_security_products
    end
  end
end
