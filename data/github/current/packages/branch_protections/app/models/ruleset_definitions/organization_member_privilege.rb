# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationMemberPrivilege < RulesetDefinition
    extend T::Sig
    include TargetMemberPrivilege
    include SourceOrganization

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.settings_org_member_privilege_rules_url(organization, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.organization_member_privilege_ruleset_url(organization, id: ruleset_id, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.organization_view_member_privilege_ruleset_history_url(organization, id: ruleset_id, history_id:, host: GitHub.host_name)
    end
  end
end
