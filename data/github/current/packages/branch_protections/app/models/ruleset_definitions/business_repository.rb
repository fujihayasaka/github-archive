# typed: strict
# frozen_string_literal: true

module RulesetDefinitions
  class BusinessRepository < RulesetDefinition
    include TargetRepository
    include SourceBusiness

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      return edit_url(ruleset_id) unless business.feature_flag_enabled?(:read_only_policy_view, default: false)
      UrlHelpers.view_repository_policy_enterprise_url(business, id: ruleset_id, host: GitHub.host_name_with_tenant)
    end

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.settings_repository_policies_enterprise_url(business, host: GitHub.host_name_with_tenant)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.settings_repository_policy_enterprise_url(business, id: ruleset_id, host: GitHub.host_name_with_tenant)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.settings_repository_policies_history_enterprise_url(business, id: ruleset_id, history_id:, host: GitHub.host_name_with_tenant)
    end
  end
end
