# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationActions < RulesetDefinition
    include TargetActions
    include SourceOrganization

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.settings_org_actions_policies_url(organization, host: GitHub.host_name_with_tenant)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.settings_org_actions_policy_url(organization, id: ruleset_id, host: GitHub.host_name_with_tenant)
    end
  end
end
