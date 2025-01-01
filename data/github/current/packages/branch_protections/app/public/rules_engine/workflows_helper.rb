# typed: strict
# frozen_string_literal: true

module RulesEngine
  module WorkflowsHelper

    MAX_SUGGESTIONS = 100

    VISIBILITY_ORDER = T.let([
      Repository::PUBLIC_VISIBILITY,
      Repository::INTERNAL_VISIBILITY,
      Repository::PRIVATE_VISIBILITY
    ], T::Array[String])

    # Find workflows that should run for a given ref_update
    #
    # Returns array of hashes containing workflow information
    sig do
      params(ref_update: Git::Ref::Update)
      .returns(T::Array[{ repository: Repository, path: String, ref: T.nilable(String), sha: T.nilable(String) }])
    end
    def self.workflows_for_ref_update(ref_update)
      repo = ref_update.repository

      branch_name = ref_update.branch_name
      rule_evaluator = branch_name ? BranchRuleEvaluator.for_repository_with_branch_name(repo, branch_name) : nil
      rules = rule_evaluator&.rule_configs || []
      workflow_rules = rules.filter { |rule| rule.rule_type == "workflows" }

      workflows_with_source = workflow_rules.flat_map do |rule_config|
        rule_config.param("workflows").map do |workflow|
          [rule_config.source, workflow]
        end
      end

      validate_workflows(workflows_with_source, target_repo: repo).filter_map do |results|
        if results[:valid]
          workflow = results[:workflow]
          workflow.delete("repository_id")
          workflow["repository"] = results[:repo]
          workflow.deep_symbolize_keys
        end
      end
    end

    sig do
      params(repo: Repository)
      .returns(T::Array[T::Hash[Symbol, String]])
    end
    def self.workflow_suggestions(repo)
      Actions::Workflow.where(repository: repo).where(imposer_repository_id: 0)
      .pluck(:name, :path).map { |name, path| { name: name, path: path } }.uniq
    end

    sig do
      params(organization: Organization, query: String)
      .returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def self.workflow_repo_suggestions(organization, query)
      matching_repos = []
      if query.present?
        scope = suggestable_repositories(organization)
        exact_match = scope.where("repositories.name = :query", query: query).first

        scope = scope.where("repositories.name like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
        if scope.present? && scope.any?
          scope = scope.order("repositories.name").limit(MAX_SUGGESTIONS)

          matching_repos = scope.to_a.prepend(exact_match).uniq.compact || []
        end
      else
        matching_repos = initial_suggestions(organization)
      end

      workflow_repo_payloads(organization, matching_repos).values
    end

    sig do
      params(source: RuleEngine::Types::RuleSource, repositories: T::Enumerable[Repository])
      .returns(T::Hash[Integer, T::Hash[Symbol, T.untyped]])
    end
    def self.workflow_repo_payloads(source, repositories)
      populate_actions_sharing_allowed(repositories).map do |repo_and_sharing|
        repo = repo_and_sharing[0]

        repo_hash = Repos::ReactPayload.current_repository_payload(repo, current_user_can_push: true)

        sharing_supported = false
        if source.is_a?(Business)
          sharing_supported = ENTERPRISE_SHAREABLE.include?(repo_and_sharing[1])
        elsif source.is_a?(Organization)
          sharing_supported = ORG_SHAREABLE.include?(repo_and_sharing[1])
        end

        repo_hash[:actionsSharing] = sharing_supported
        repo_hash[:refCacheKey] = ref_list_cache_key(repo)

        if source.is_a?(Business) && repo.owner&.organization?
          repo_hash[:owner] = RulesEngine::ReactPayload.simple_organization_payload(T.cast(repo.owner, Organization))
        end

        [repo.id, repo_hash]
      end.to_h
    end

    ORG_SHAREABLE = T.let([Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_ORGANIZATION, Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_BUSINESS], T::Array[String])
    ENTERPRISE_SHAREABLE = T.let([Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_BUSINESS], T::Array[String])

    # Validate workflows
    #
    # Returns array of hashes containing workflow information
    sig do
      params(source_and_workflows: T::Array[[RuleEngine::Types::RuleSource, T::Hash[String, T.untyped]]], target_repo: T.nilable(Repository))
      .returns(T::Array[{ workflow: T::Hash[String, T.untyped], valid: T::Boolean, repo: T.nilable(Repository), error_code: T.nilable(Symbol) }])
    end
    def self.validate_workflows(source_and_workflows, target_repo: nil)
      repos = Repository.active.where(id: source_and_workflows.map { |w| w[1]["repository_id"] }).to_h { |v| [v.id, v] }
      sharing_info = populate_actions_sharing_allowed(repos.values).to_h { |v| [v[0].id, v[1]] }

      source_and_workflows.map do |source, workflow|
        repo = repos[workflow["repository_id"]]
        next { workflow:, repo:, valid: false, error_code: :repo_not_found } unless repo

        # Currently we only support orgs
        # Ensure target repo is still owned by the org
        if source.is_a?(Organization)
          if source.id != repo.owner&.id
            next { workflow:, repo:, valid: false, error_code: :not_in_org }
          end

          next { workflow:, repo:, valid: false, error_code: :actions_sharing_disabled } unless ORG_SHAREABLE.include?(sharing_info[repo.id])
        elsif source.is_a?(Business)
          if source.id != repo.owner&.business&.id
            next { workflow:, repo:, valid: false, error_code: :not_in_enterprise }
          end

          next { workflow:, repo:, valid: false, error_code: :actions_sharing_disabled } unless ENTERPRISE_SHAREABLE.include?(sharing_info[repo.id])
        else
          next { workflow:, repo:, valid: false, error_code: :source_not_supported }
        end

        if !workflow["allow_invalid_path"]
          # Validate the workflow path starts with .github/workflows or .github/workflows-lab/ (ring 0 Actions canaries)
          next { workflow:, repo:, valid: false, error_code: :workflow_path_invalid } unless workflow["path"].start_with?(".github/workflows/", ".github/workflows-lab/")

          # .github/workflows/<workflow>.yml since we don't support subdirectories
          next { workflow:, repo:, valid: false, error_code: :workflow_path_no_subdir } unless workflow["path"].split("/").length == 3
        end

        # Validate SHA and Ref
        if workflow["ref"]
          next { workflow:, repo:, valid: false, error_code: :ref_not_found } if repo.refs[workflow["ref"]].nil?
        end

        if workflow["sha"]
          next { workflow:, repo:, valid: false, error_code: :sha_not_found } unless repo.is_commit_in_branch_or_tag?(workflow["sha"])
          next { workflow:, repo:, valid: false, error_code: :workflow_not_found } unless repo.includes_file_at_commit?(workflow["path"], workflow["sha"])
        else
          next { workflow:, repo:, valid: false, error_code: :workflow_not_found } unless repo.includes_file?(workflow["path"], workflow["ref"])
        end

        # If a target_repo was passed in, validate visibility requirements
        if target_repo && T.must(VISIBILITY_ORDER.index(target_repo.visibility)) < T.must(VISIBILITY_ORDER.index(repo.visibility))
          next { workflow:, repo:, valid: false, error_code: :visibility_mismatch }
        end

        # Validate that actions has not been disabled for the source or target repo at the org or enterprise level
        if source.feature_enabled_for_source?(:enterprise_workflow_rule)
          if target_repo.present? && actions_disabled_for_target_repo_by_rule_source?(target_repo, workflow, source)
            next { workflow:, repo:, valid: false, error_code: :actions_disabled }
          end
        else
          if target_repo&.actions_disabled_by_owner?
            next { workflow:, repo:, valid: false, error_code: :actions_disabled }
          end
        end

        if repo.actions_disabled_by_owner?
          next { workflow:, repo:, valid: false, error_code: :actions_disabled_for_source_repo }
        end

        { workflow:, repo:, valid: true, error_code: nil }
      end
    end

    sig do
      params(repo: T::nilable(Repository), workflow: T::Hash[String, T.untyped], source: RuleEngine::Types::RuleSource)
      .returns(T::Boolean)
    end
    def self.actions_disabled_for_target_repo_by_rule_source?(repo, workflow, source)
      if source.is_a?(Organization)
        repo&.actions_disabled_by_owner?
      elsif source.is_a?(Business)
        T.cast(repo&.owner, Organization).actions_disabled_by_owner?
      end
    end

    sig do
      params(repo: Repository)
      .returns(T::Boolean)
    end
    def self.enabled_workflow_rule_for_repo?(repo)
      rules = RepositoryRuleset.load_for(source: repo, include_parents: true)
      rules.any? { |r| (r.enabled? || r.evaluate?) && r.rule_configurations.any? { |rc| rc.rule_type == "workflows" } }
    end

    # Returns array of repositories with their share level (strings defined in Configurable::ActionsRepositorySharePolicy)
    sig do
      params(repositories: T::Enumerable[Repository])
      .returns(T::Array[[Repository, String]])
    end
    private_class_method def self.populate_actions_sharing_allowed(repositories)
      repositories = repositories.to_a
      return [] unless repositories.any?

      repos_with_share_policy = Configuration::Entry
        .targeting_repository_ids(repositories.map(&:id))
        .named(Configurable::ActionsRepositorySharePolicy::KEY)
        .select(:target_id, :value).to_a
      internal_repo_ids = InternalRepository.where(repository_id: repositories.map(&:id)).pluck(:repository_id)

      share_policy_by_repo_id = repos_with_share_policy.map { |record| [record.target_id, record.value] }.to_h
      repositories.filter_map do |repo|
        share_level = Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_BUSINESS
        if internal_repo_ids.include?(repo.id) || repo.private?
          share_level = share_policy_by_repo_id[repo.id]
        end
        [repo, share_level]
      end
    end

    sig do
      params(organization: Organization)
      .returns(T::untyped) # Needs to return a Repository ActiveRecord relation but that doesn't seem supported
    end
    private_class_method def self.initial_suggestions(organization)
      scope = suggestable_repositories(organization)
      scope = scope.recently_updated.order("repositories.name").limit(MAX_SUGGESTIONS)
    end

    sig do
      params(organization: Organization)
      .returns(T::untyped) # Needs to return a Repository ActiveRecord relation but that doesn't seem supported
    end
    private_class_method def self.suggestable_repositories(organization)
      Repository.active.where(owner_id: organization.id).includes(:owner)
    end

    # Copied from BranchesHelper
    sig do
      params(repository: Repository)
      .returns(String)
    end
    private_class_method def self.ref_list_cache_key(repository)
      "v0:#{repository.refset_updated_at.to_f}"
    end

  end
end
