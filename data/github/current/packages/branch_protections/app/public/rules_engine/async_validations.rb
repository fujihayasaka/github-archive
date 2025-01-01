# typed: strict
# frozen_string_literal: true

module RulesEngine
  module AsyncValidations

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        type: String,
        value: T::Hash[String, T.untyped]
      ).returns(T::Boolean)
    end
    def self.validate_value(source, type, value)
      case type
      when "ruleset_name"
        return true if validate_ruleset_name(source, value["name"], id: value["id"])
      when "condition_target"
        return true if validate_condition_target(source, value["conditionTarget"], value["target"], id: value["id"])
      when "reachable_sha"
        return true if validate_reachable_sha(source, value)
      end

      false
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        name: String,
        id: T.nilable(Integer)
      ).returns(T::Boolean)
    end
    private_class_method def self.validate_ruleset_name(source, name, id:)
      return false if name.blank?

      GitHub.dogstats.distribution_time("repository_rules_engine.async_validations.ruleset_unique_name_query.total_duration") do
        query = source.rulesets.where(name: name)
        query = query.where.not(id: id) unless id.nil?

        query.empty?
      end
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        target_pattern: String,
        target: String,
        id: T.nilable(Integer)
      ).returns(T::Boolean)
    end
    private_class_method def self.validate_condition_target(source, target_pattern, target, id:)
      if target_pattern.blank?
        false
      else
        if target == "ref_name"
          if target_pattern =~ GitHub::SHA_LIKE_REF_NAME || target_pattern == "refs/heads/HEAD"
            false
          else
            true
          end
        elsif target == "repository_name"
          true
        else
          true
        end
      end
    end

    sig do
      params(
        source: RuleEngine::Types::RuleSource,
        value: T::Hash[String, T.untyped],
      ).returns(T::Boolean)
    end
    private_class_method def self.validate_reachable_sha(source, value)
      repo = if source.is_a?(::Organization)
        return false if value["repo_id"].nil?
        repo = source.repositories.find_by(id: value["repo_id"])
        return false unless repo
        repo
      elsif source.is_a?(Business)
        return false if value["repo_id"].nil?
        repo = Repository.where(owner: { business_id: source.id }).find_by(id: value["repo_id"])
        return false unless repo
        repo
      else
        source
      end
      return false if value["sha"].nil?

      repo.is_commit_in_branch_or_tag?(value["sha"])
    end
  end
end
