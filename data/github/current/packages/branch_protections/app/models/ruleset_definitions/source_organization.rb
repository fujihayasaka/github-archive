# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module SourceOrganization

    sig { returns(Organization) }
    def organization
      @source
    end

    sig { returns(String) }
    def display_type
      "Organization"
    end

    sig { returns(String) }
    def display_source_name
      @source.name_with_display_owner
    end

    sig { returns(T::Array[String]) }
    def source_required_condition_targets
      # org rules require a repository and whatever the ruleset target requires
      ["repository"]
    end

    sig { returns(T::Boolean) }
    def supports_evaluate_mode?
      # all org rulesets support evaluate mode
      true
    end

    sig { returns(T::Array[String]) }
    def validation_errors
      []
    end

    sig { returns(T::Boolean) }
    def is_valid_for_source?
      organization.plan_supports?(:enterprise_rulesets)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def event_payload
      {
        ruleset_source_type: display_type,
        org: organization
      }
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      # org path goes to org admin view since only org admins can reach this org endpoint
      "#{GitHub.url}/organizations/#{organization.display_login}/settings/rules/#{ruleset_id}"
    end

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.organization_rulesets_url(organization, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.organization_ruleset_url(organization, id: ruleset_id, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.organization_view_ruleset_history_url(organization, id: ruleset_id, history_id:, host: GitHub.host_name)
    end

    sig { params(ruleset: RepositoryRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      return true if object == organization
      return false unless is_valid_for_source?
      return false unless object.is_a?(Repository)
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: object)
      ruleset.satisfies_conditions?(context, "repository")
    end
  end
end
