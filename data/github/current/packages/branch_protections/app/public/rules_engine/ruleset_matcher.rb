# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RulesetMatcher
    RulesetMatchResult = T.type_alias do
      {
        rulesetId: Integer,
        url: T.nilable(String),
        count: T.nilable(Integer),
        sampleTargetNames: T.nilable(T::Array[String]),
        errorMessage: T.nilable(String),
      }
    end

    MAX_MATCHING_TARGETS = 25000
    MAX_SAMPLE_NAMES = 10
    # Time buffer (in ms) reserved before the request hard timeout to allow a graceful response.
    TARGET_COUNT_TIME_BUFFER_MS = 2000
    # How often to check the request time budget while iterating over refs. Balances per-ref overhead
    # against worst-case overshoot (overshoot = this many refs' worth of work past the budget).
    TARGET_COUNT_BUDGET_CHECK_INTERVAL = 25

    sig { params(domain: RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource], source: RuleEngine::Types::RuleSource, ruleset_ids: T::Array[Integer], supported_targets: T::Array[String]).returns(T::Array[RulesetMatchResult]) }
    def self.rulesets_target_count(domain, source, ruleset_ids, supported_targets:)
      return [] if ruleset_ids.empty?

      rulesets = domain.rulesets_from_ids(source, ruleset_ids, include_inherited: false, targets: supported_targets)

      if source.is_a?(Business)
        calculate_organizations_count(source, rulesets, limit_samples: MAX_SAMPLE_NAMES)
      elsif source.is_a?(Organization)
        calculate_repositories_count(source, rulesets, limit_samples: MAX_SAMPLE_NAMES)
      elsif source.is_a?(Repository)
        rulesets += retrieve_org_rulesets(domain, source, ruleset_ids - rulesets.map(&:id), supported_targets)
        calculate_refs_count(source, rulesets, limit_samples: MAX_SAMPLE_NAMES)
      else
        []
      end
    end

    sig { params(domain: RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource], repository: Repository, ruleset_ids: T::Array[Integer], supported_targets: T::Array[String]).returns(T::Array[RuleEngine::IRuleset]) }
    private_class_method def self.retrieve_org_rulesets(domain, repository, ruleset_ids, supported_targets)
      return [] if (org = repository.organization).nil?
      return [] if ruleset_ids.empty?

      domain.rulesets_from_ids(org, ruleset_ids, include_inherited: false, targets: supported_targets)
    end

    sig { params(enterprise: Business, rulesets: T::Array[RuleEngine::IRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.calculate_organizations_count(enterprise, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      orgs_count = enterprise.organizations.count
      if orgs_count > MAX_MATCHING_TARGETS
        GitHub.dogstats.count("rulesets.async_target_count_max_limit_reached", orgs_count, tags: ["target:organizations"])
        rulesets.map do |ruleset|
          T.cast({
            rulesetId: ruleset.id,
            errorMessage: "Unable to display affected targets due to a large number of organizations in this enterprise."
          }, RulesetMatchResult)
        end
      else
        rulesets.map do |ruleset|
          matching_targets = self.extract_matching_orgs(enterprise, ruleset)
          T.cast({
            rulesetId: ruleset.id,
            count: matching_targets.size,
            sampleTargetNames: limit_samples ? matching_targets.take(limit_samples) : matching_targets,
          }, RulesetMatchResult)
        end
      end
    end

    sig { params(organization: Organization, rulesets: T::Array[RuleEngine::IRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.calculate_repositories_count(organization, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      property_rulesets, repo_name_rulesets = rulesets.partition do |ruleset|
        ruleset.conditions.any? { |condition| condition.target == "repository_property" }
      end

      GitHub.dogstats.count("rulesets.async_target_count", property_rulesets.count, tags: ["target:property"])
      GitHub.dogstats.count("rulesets.async_target_count", repo_name_rulesets.count, tags: ["target:name"])

      repo_name_ruleset_target_count(organization, repo_name_rulesets, limit_samples: limit_samples) + property_rulesets_target_count(organization, property_rulesets)
    end

    sig { params(repository: Repository, rulesets: T::Array[RuleEngine::IRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.calculate_refs_count(repository, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      GitHub.dogstats.count("rulesets.async_target_count", rulesets.count, tags: ["target:branch_tag"])

      rulesets.map do |ruleset|
        next unless ruleset.target == "branch" || ruleset.target == "tag"

        type, refs = ruleset.target == "branch" ? ["branches", repository.heads] : ["tags", repository.tags]

        refs_count = refs.size
        if refs_count > MAX_MATCHING_TARGETS
          GitHub.dogstats.count("rulesets.async_target_count_max_limit_reached", refs_count, tags: ["target:#{type}"])
          T.cast({ rulesetId: ruleset.id, errorMessage: "Unable to display affected targets due to a large number of #{type} in this repository." }, RulesetMatchResult)
        else
          begin
            GitHub::RequestDurationManager.raise_if_time_budget_is_over(time_buffer_ms: TARGET_COUNT_TIME_BUFFER_MS) do
              matching_targets = self.extract_matching_ref_names(refs, ruleset, repository)
              T.cast({
                rulesetId: ruleset.id,
                count: matching_targets.count,
                sampleTargetNames: limit_samples ? matching_targets.take(limit_samples) : matching_targets,
              }, RulesetMatchResult)
            end
          rescue GitHub::RequestDurationManager::TimeBudgetIsOverError
            GitHub.dogstats.increment("rulesets.async_target_count_timeout", tags: ["target:branch_tag"])
            nil
          end
        end
      end.compact
    end

    sig { params(refs: T.untyped, ruleset: RuleEngine::IRuleset, repository: Repository).returns(T::Array[String]) }
    private_class_method def self.extract_matching_ref_names(refs, ruleset, repository)
      refs.each_with_index.filter_map do |ref, i|
        if i > 0 && (i % TARGET_COUNT_BUDGET_CHECK_INTERVAL).zero?
          GitHub::RequestDurationManager.raise_if_time_budget_is_over(time_buffer_ms: TARGET_COUNT_TIME_BUFFER_MS)
        end
        context = RuleEngine::Conditions::Targets::Ref.new(repository: repository, ref_name: ref.qualified_name)
        ref.name if ruleset.satisfies_conditions?(context, RuleEngine::Conditions::ConditionTarget::TargetObject::Ref)
      end
    end

    sig { params(ruleset: RuleEngine::IRuleset, repository: Repository, qualified_ref_name: String).returns(T::Boolean) }
    def self.should_evaluate_ref?(ruleset, repository, qualified_ref_name)
      return false unless qualified_ref_name.present?

      context = RuleEngine::Conditions::Targets::Ref.new(repository:, ref_name: qualified_ref_name)
      ruleset.should_evaluate?(context)
    end

    sig { params(source: Organization, rulesets: T::Array[RuleEngine::IRuleset]).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.property_rulesets_target_count(source, rulesets)
      return [] if rulesets.empty?

      rulesets.map do |ruleset|
        property_condition = ruleset.conditions.find { |condition| condition.target == "repository_property" }
        phrase = source.es_query_property_ruleset_conditions(T.must(property_condition))

        url = generate_repos_query_path(source, T.must(property_condition))

        T.cast({ rulesetId: ruleset.id, count: self.execute_es_count_query(phrase), url:,  }, RulesetMatchResult)
      end
    end

    sig { params(source: Organization, rulesets: T::Array[RuleEngine::IRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.repo_name_ruleset_target_count(source, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      repos_count = source.repositories.count
      if repos_count > MAX_MATCHING_TARGETS
        GitHub.dogstats.count("rulesets.async_target_count_max_limit_reached", repos_count, tags: ["target:repositories"])
        rulesets.map do |ruleset|
          T.cast({
            rulesetId: ruleset.id,
            errorMessage: "Unable to display affected targets due to a large number of repositories in this organization."
          }, RulesetMatchResult)
        end
      else
        rulesets.map do |ruleset|
          matching_targets = self.extract_matching_repos(source, ruleset)
          T.cast({
            rulesetId: ruleset.id,
            count: matching_targets.size,
            sampleTargetNames: limit_samples ? matching_targets.take(limit_samples) : matching_targets,
          }, RulesetMatchResult)
        end
      end
    end

    sig { params(enterprise: Business, ruleset: RuleEngine::IRuleset).returns(T::Array[String]) }
    private_class_method def self.extract_matching_orgs(enterprise, ruleset)
      orgs = enterprise.organizations.to_a.sort_by { |org| org.display_login }

      orgs.filter_map do |org|
        target = Targeting::Targets::Organization.new(organization: org)
        org.display_login if ruleset.satisfies_conditions?(target, RuleEngine::Conditions::ConditionTarget::TargetObject::Organization)
      end
    end

    sig { params(org: Organization, ruleset: RuleEngine::IRuleset).returns(T::Array[String]) }
    private_class_method def self.extract_matching_repos(org, ruleset)
      repos = org.repositories.to_a.sort_by { |repo| repo.name }

      repos.filter_map do |repo|
        target = Targeting::Targets::Repository.new(repository: repo)
        repo.name if ruleset.satisfies_conditions?(target, RuleEngine::Conditions::ConditionTarget::TargetObject::Repository)
      end
    end

    sig { params(phrase: String).returns(T.nilable(Integer)) }
    private_class_method def self.execute_es_count_query(phrase)
      GitHub.dogstats.distribution_time("rulesets.async_target_count_query") do
        query = Search::Queries::RepoQuery.new(
          current_user: nil,
          phrase: phrase,
          include_forks: true,
          skip_permission_check: true,
        )

        query.count_with_timeout.total
      rescue ::ElastomerClient::Client::Error
        nil
      end
    end

    sig { params(source: Organization, property_condition: RuleEngine::IRuleCondition).returns(String) }
    private_class_method def self.generate_repos_query_path(source, property_condition)
      url = UrlHelpers.org_repositories_path(source)
      phrase = source.build_phrase_from_property_condition(property_condition)

      query = {
        q: phrase,
      }.to_param

      url + "?#{query}"
    end
  end
end
