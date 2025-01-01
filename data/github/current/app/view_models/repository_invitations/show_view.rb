# typed: true
# frozen_string_literal: true

module RepositoryInvitations
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ApplicationHelper

    attr_reader :invitation

    def inviter
      self.invitation.inviter
    end

    def repository_owner
      invitation.repository.owner
    end

    def organization_name
      repository_owner.name
    end

    def invitee_two_factor_requirement_non_compliant?
      !invitation.repository.two_factor_requirement_met_by?(current_user)
    end

    def block_acceptance_due_to_ofac_compliance?
      invitation.repository.private? && current_user.has_any_trade_restrictions?
    end

    def invitee_can_accept_invitation?
      !(block_acceptance_due_to_ofac_compliance? || invitee_two_factor_requirement_non_compliant?)
    end

    def audit_log_disclosure_url
      if repository_owner.organization?
        "#{GitHub.help_url}/articles/reviewing-the-audit-log-for-your-organization/#search-based-on-the-action-performed"
      else
        "#{GitHub.help_url}/articles/reviewing-your-security-log/#the-repo-category"
      end
    end

    def invitation_disclosure_article_url
      if repository_owner.organization?
        "#{GitHub.help_url}/articles/repository-permission-levels-for-an-organization"
      else
        "#{GitHub.help_url}/articles/permission-levels-for-a-user-account-repository"
      end
    end
  end
end
