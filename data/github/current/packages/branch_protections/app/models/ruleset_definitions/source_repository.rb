# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module SourceRepository
    extend T::Sig

    # This is the repo `owner` if it is an organization.
    # This is not the repo `organization` which for user-owned forks is the org the repo forked from
    sig { returns(T.nilable(User)) }
    def organization
      repo.owner.is_a?(Organization) ? repo.owner : nil
    end

    sig { returns(Repository) }
    def repo
      @source
    end

    sig { returns(String) }
    def display_type
      "Repository"
    end

    sig { returns(T::Array[String]) }
    def source_required_condition_targets
      # repo rulesets do not require any additional condition targets
      []
    end

    sig { returns(T::Boolean) }
    def supports_evaluate_mode?
      # only repo rulesets in orgs support evaluate mode
      repo.in_organization?
    end

    sig { returns(T::Boolean) }
    def is_valid_for_source?
      true
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def event_payload
      payload =
      {
        ruleset_source_type: display_type,
        repo: @source
      }

      payload[:org] = @source.owner if @source&.owner.is_a?(Organization)
      payload
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      # repo path goes to read-only view
      "#{repo.permalink}/rules/#{ruleset_id}"
    end

    sig { returns(String) }
    def edit_index_url
      UrlHelpers.repository_rulesets_url(repo.owner, repo, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def edit_url(ruleset_id)
      UrlHelpers.repository_ruleset_url(repo.owner, repo, id: ruleset_id, host: GitHub.host_name)
    end

    sig { params(ruleset_id: Integer, history_id: Integer).returns(String) }
    def history_url(ruleset_id, history_id)
      UrlHelpers.view_ruleset_history_url(repository: repo, user_id: repo.owner, id: ruleset_id, history_id:, host: GitHub.host_name)
    end

    def reconcile_merge_queues
      # use @source not repo, because it may be nil and repo demands a Repository
      MergeQueues.reconcile_queues_and_rulesets!(@source) if @source
      nil
    end

    sig { params(ruleset: RepositoryRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      return true if object == repo
      return false unless object.is_a?(Repository)
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: object)
      ruleset.satisfies_conditions?(context, "repository")
    end
  end
end
