# typed: true
# frozen_string_literal: true

module Users
  module OrganizationEnforcementMethods
    def kicked_out_due_to_two_factor_enforcement?
      T.bind(self, Orgs::OverviewView)
      !direct_or_team_member? &&
          Organization::RemovedMemberNotification.new(organization, current_user)
          .two_factor_requirement_non_compliance?
    end

    def removed_due_to_saml_enforcement?
      T.bind(self, Orgs::OverviewView)
      !organization.saml_sso_requirement_met_by?(current_user) &&
        Organization::RemovedMemberNotification.new(organization, current_user)
          .saml_external_identity_missing?
    end
  end
end
