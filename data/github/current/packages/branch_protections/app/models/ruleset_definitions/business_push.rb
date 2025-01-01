# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class BusinessPush < RulesetDefinition
    include TargetPush
    include SourceBusiness

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      # enterprise path goes to enterprise admin view since only enterprise admins can reach this enterprise endpoint
      edit_url(ruleset_id)
    end

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.settings_code_rules_enterprise_url(business, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.settings_code_ruleset_enterprise_url(business, id: ruleset_id, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.settings_code_view_ruleset_history_enterprise_url(business, id: ruleset_id, history_id:, host: GitHub.host_name)
    end

    sig { params(targets: T.nilable(T::Array[String])).returns(T::Boolean) }
    def applies_to_targets?(targets)
      super && ruleset_feature_enabled?
    end

    sig { params(ruleset: RepositoryRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      if super
        return RulesetDefinitions::RulesetDefinition.factory(object, "Repository", "push").is_valid? if object.is_a?(Repository)
        true
      else
        false
      end
    end

    sig { returns(T::Boolean) }
    def ruleset_feature_enabled?
      @source.push_rulesets_enabled?
    end

    sig { returns(T::Boolean) }
    def supports_delegated_bypass?
      @source.delegated_bypass_enabled?
    end
  end
end
