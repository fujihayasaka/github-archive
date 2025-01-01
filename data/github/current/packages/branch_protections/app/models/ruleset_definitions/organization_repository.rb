# typed: strict
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationRepository < RulesetDefinition
    include TargetRepository
    include SourceOrganization

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      return edit_url(ruleset_id) unless organization.feature_flag_enabled?(:read_only_policy_view, default: false)
      UrlHelpers.view_organization_repository_policy_url(organization, id: ruleset_id, host: GitHub.host_name_with_tenant)
    end

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.settings_org_repository_policies_url(organization, host: GitHub.host_name_with_tenant)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.edit_organization_repository_policy_url(organization, id: ruleset_id, host: GitHub.host_name_with_tenant)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.organization_view_repository_policy_history_url(organization, id: ruleset_id, history_id:, host: GitHub.host_name_with_tenant)
    end
  end
end
