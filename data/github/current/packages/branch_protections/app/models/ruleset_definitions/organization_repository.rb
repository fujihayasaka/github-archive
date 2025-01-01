# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationRepository < RulesetDefinition
    include TargetRepository
    include SourceOrganization

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      edit_url(ruleset_id)
    end

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.settings_org_repository_policies_url(organization, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.organization_repository_policy_url(organization, id: ruleset_id, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.organization_view_repository_policy_history_url(organization, id: ruleset_id, history_id:, host: GitHub.host_name)
    end
  end
end
