# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RulesetMatcher
    extend T::Sig
    RulesetMatchResult = T.type_alias do
      {
        rulesetId: Integer,
        count: T.nilable(Integer),
        sampleTargetNames: T.nilable(T::Array[String]),
        errorMessage: T.nilable(String),
      }
    end

    MAX_MATCHING_TARGETS = 25000
    MAX_SAMPLE_NAMES = 10

    sig { params(source: RuleEngine::Types::RuleSource, user: T.nilable(User)).returns(T::Boolean) }
    def self.async_preview_ff_enabled?(source, user)
      return true if user&.feature_enabled?(:ruleset_async_preview)
      return true if source.is_a?(Organization) && source.feature_enabled?(:property_ruleset_async_preview)

      false
    end

    sig { params(source: Business, ruleset: RepositoryRuleset).returns(T.any(T::Array[String], String)) }
    def self.matching_organization_targets_or_message(source, ruleset)
      return "Unable to display affected targets due to a large number of organizations in this enterprise." if source.organizations.count > MAX_MATCHING_TARGETS

      matching_targets = []

      source.organizations.to_a.sort_by { _1.display_login }.each do |org|
        context = RuleEngine::Conditions::RulesetTargetContext.new(organization: org)
        matching_targets.push(org.display_login) if ruleset.satisfies_conditions?(context, "organization")
      end

      matching_targets
    end

    sig { params(source: Organization, ruleset: RepositoryRuleset).returns(T.any(T::Array[String], String)) }
    def self.matching_repository_targets_or_message(source, ruleset)
      return "" if ruleset.conditions.any? { |condition| condition.repository_property? }

      if source.feature_enabled?(:ruleset_skip_condition_count)
        return ""
      end

      fetch_ruleset_data = T.must(repo_name_ruleset_target_count(source, [ruleset]).first)
      return fetch_ruleset_data[:errorMessage] if fetch_ruleset_data[:errorMessage]

      fetch_ruleset_data[:sampleTargetNames]
    end

    sig { params(source: RuleEngine::Types::RuleSource, ruleset_ids: T::Array[Integer]).returns(T::Array[RulesetMatchResult]) }
    def self.rulesets_target_count(source, ruleset_ids)
      return [] if ruleset_ids.empty?

      rulesets = source.rulesets.where(id: ruleset_ids).to_a

      if source.is_a?(Business)
        calculate_organizations_count(source, rulesets, limit_samples: MAX_SAMPLE_NAMES)
      elsif source.is_a?(Organization)
        calculate_repositories_count(source, rulesets, limit_samples: MAX_SAMPLE_NAMES)
      elsif source.is_a?(Repository)
        rulesets += retrieve_org_rulesets(source, ruleset_ids - rulesets.map(&:id))
        calculate_refs_count(source, rulesets, limit_samples: MAX_SAMPLE_NAMES)
      else
        []
      end
    end

    sig { params(repository: Repository, ruleset_ids: T::Array[Integer]).returns(T::Array[RepositoryRuleset]) }
    private_class_method def self.retrieve_org_rulesets(repository, ruleset_ids)
      return [] if repository.organization.nil?
      return [] if ruleset_ids.empty?

      T.must(repository.organization).rulesets.where(id: ruleset_ids).to_a
    end

    sig { params(enterprise: Business, rulesets: T::Array[RepositoryRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.calculate_organizations_count(enterprise, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      if enterprise.organizations.count > MAX_MATCHING_TARGETS
        rulesets.map do |ruleset|
          T.cast({
            rulesetId: T.must(ruleset.id),
            errorMessage: "Unable to display affected targets due to a large number of organizations in this enterprise."
          }, RulesetMatchResult)
        end
      else
        rulesets.map do |ruleset|
          matching_targets = self.extract_matching_orgs(enterprise, ruleset)
          T.cast({
            rulesetId: T.must(ruleset.id),
            count: matching_targets.size,
            sampleTargetNames: limit_samples ? matching_targets.take(limit_samples) : matching_targets,
          }, RulesetMatchResult)
        end
      end
    end

    sig { params(organization: Organization, rulesets: T::Array[RepositoryRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.calculate_repositories_count(organization, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      property_rulesets, repo_name_rulesets = rulesets.partition do |ruleset|
        ruleset.conditions.any? { |condition| condition.target == "repository_property" }
      end

      GitHub.dogstats.count("rulesets.async_target_count", property_rulesets.count, tags: ["target:property"])
      GitHub.dogstats.count("rulesets.async_target_count", repo_name_rulesets.count, tags: ["target:name"])

      repo_name_ruleset_target_count(organization, repo_name_rulesets, limit_samples: limit_samples) + property_rulesets_target_count(organization, property_rulesets)
    end

    sig { params(source: Repository, ruleset: RepositoryRuleset).returns(T.any(T::Array[String], String)) }
    def self.matching_ref_targets_or_message(source, ruleset)
      return [] unless ruleset.targets_branch? || ruleset.targets_tag?

      type = ruleset.targets_branch? ? "branches" : "tags"
      refs = ruleset.targets_branch? ? source.heads : source.tags

      return "Unable to display affected targets due to a large number of #{type} in this repository." if refs.size > MAX_MATCHING_TARGETS

      matching_targets = []

      refs.each do |ref|
        context = RuleEngine::Conditions::RulesetTargetContext.new(repository: source, ref_name: ref.qualified_name)
        matching_targets.push(ref.name) if ruleset.satisfies_conditions?(context, "ref")
      end

      matching_targets
    end

    sig { params(repository: Repository, rulesets: T::Array[RepositoryRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.calculate_refs_count(repository, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      GitHub.dogstats.count("rulesets.async_target_count", rulesets.count, tags: ["target:branch_tag"])

      rulesets.map do |ruleset|
        next unless ruleset.targets_branch? || ruleset.targets_tag?

        type, refs = ruleset.targets_branch? ? ["branches", repository.heads] : ["tags", repository.tags]

        if refs.size > MAX_MATCHING_TARGETS
          T.cast({ rulesetId: ruleset.id, errorMessage: "Unable to display affected targets due to a large number of #{type} in this repository." }, RulesetMatchResult)
        else
          matching_targets = self.extract_matching_ref_names(refs, ruleset, repository)
          T.cast({
            rulesetId: ruleset.id,
            count: matching_targets.count,
            sampleTargetNames: limit_samples ? matching_targets.take(limit_samples) : matching_targets,
          }, RulesetMatchResult)
        end
      end.compact
    end

    sig { params(refs: T.untyped, ruleset: RepositoryRuleset, repository: Repository).returns(T::Array[String]) }
    private_class_method def self.extract_matching_ref_names(refs, ruleset, repository)
      refs.filter_map do |ref|
        context = RuleEngine::Conditions::RulesetTargetContext.new(repository: repository, ref_name: ref.qualified_name)
        ref.name if ruleset.satisfies_conditions?(context, "ref")
      end
    end

    sig { params(ruleset: RepositoryRuleset, repository: Repository, qualified_ref_name: String).returns(T::Boolean) }
    def self.should_evaluate_ref?(ruleset, repository, qualified_ref_name)
      return false unless qualified_ref_name.present?

      context = RuleEngine::Conditions::RulesetTargetContext.new(repository:, ref_name: qualified_ref_name)
      ruleset.should_evaluate?(context)
    end

    sig { params(source: Organization, rulesets: T::Array[RepositoryRuleset]).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.property_rulesets_target_count(source, rulesets)
      return [] if rulesets.empty?

      rulesets.map do |ruleset|
        phrase = source.es_query_property_ruleset_conditions(ruleset)

        T.cast({ rulesetId: T.must(ruleset.id), count: self.execute_es_count_query(phrase) }, RulesetMatchResult)
      end
    end

    sig { params(source: Organization, rulesets: T::Array[RepositoryRuleset], limit_samples: T.nilable(Integer)).returns(T::Array[RulesetMatchResult]) }
    private_class_method def self.repo_name_ruleset_target_count(source, rulesets, limit_samples: nil)
      return [] if rulesets.empty?

      if source.repositories.count > MAX_MATCHING_TARGETS
        rulesets.map do |ruleset|
          T.cast({
            rulesetId: T.must(ruleset.id),
            errorMessage: "Unable to display affected targets due to a large number of repositories in this organization."
          }, RulesetMatchResult)
        end
      else
        rulesets.map do |ruleset|
          matching_targets = self.extract_matching_repos(source, ruleset)
          T.cast({
            rulesetId: T.must(ruleset.id),
            count: matching_targets.size,
            sampleTargetNames: limit_samples ? matching_targets.take(limit_samples) : matching_targets,
          }, RulesetMatchResult)
        end
      end
    end

    sig { params(enterprise: Business, ruleset: RepositoryRuleset).returns(T::Array[String]) }
    private_class_method def self.extract_matching_orgs(enterprise, ruleset)
      orgs = enterprise.organizations.to_a.sort_by { |org| org.display_login }

      orgs.filter_map do |org|
        context = RuleEngine::Conditions::RulesetTargetContext.new(organization: org)
        org.display_login if ruleset.satisfies_conditions?(context, "organization")
      end
    end

    sig { params(org: Organization, ruleset: RepositoryRuleset).returns(T::Array[String]) }
    private_class_method def self.extract_matching_repos(org, ruleset)
      repos = org.repositories.to_a.sort_by { |repo| T.must(repo.name) }

      repos.filter_map do |repo|
        context = RuleEngine::Conditions::RulesetTargetContext.new(repository: repo)
        repo.name if ruleset.satisfies_conditions?(context, "repository")
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
  end
end
