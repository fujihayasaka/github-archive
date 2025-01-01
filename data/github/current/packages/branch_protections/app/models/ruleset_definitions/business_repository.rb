# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class BusinessRepository < RulesetDefinition
    include TargetRepository
    include SourceBusiness

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      # enterprise path goes to enterprise admin view since only enterprise admins can reach this enterprise endpoint
      edit_url(ruleset_id)
    end

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.settings_repository_policies_enterprise_url(business, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.settings_repository_policy_enterprise_url(business, id: ruleset_id, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.settings_repository_policies_history_enterprise_url(business, id: ruleset_id, history_id:, host: GitHub.host_name)
    end
  end
end
