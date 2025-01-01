# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class RefNameTarget < ConditionTarget
      DEFAULT_BRANCH_PATTERN = "~DEFAULT_BRANCH"
      ALL_PATTERN = "~ALL"

      TRANSLATED_PATTERNS = T.let([
        DEFAULT_BRANCH_PATTERN,
        ALL_PATTERN
      ], T::Array[String])

      sig do
        override.params(
          targetable: Targetable,
          ruleset_target: String,
          parameters: T.untyped
        ).returns(T::Boolean)
      end
      def run_condition(targetable, ruleset_target, parameters)
        return false unless (repository = targetable.repository) && (ref_name = targetable.ref_name)

        parameters = { "include": [], "exclude": [] } if parameters.nil?

        case ruleset_target
        when "branch"
          return false unless ref_name.starts_with?("refs/heads/")
        when "tag"
          return false unless ref_name.starts_with?("refs/tags/")
        else
          return false
        end

        include_list = replace_parameters(repository, ruleset_target, parameters["include"])
        exclude_list = replace_parameters(repository, ruleset_target, parameters["exclude"])

        match_include_exclude(ref_name, include_list, exclude_list) do |candidate, target|
          File.fnmatch?(candidate, target, File::FNM_PATHNAME)
        end
      end

      sig { override.returns(T::Boolean) }
      def internal?
        false
      end

      sig { override.returns(String) }
      def target_object
        "ref"
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_ruleset_targets
        [:branch, :tag]
      end

      # Sources that support this condition target
      sig { override.returns(T::Array[Symbol]) }
      def supported_sources
        [:business, :organization, :repository]
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(validator: method(:ensure_valid_include_exclude_condition))

        schema.add_field(ParameterSchema::Array.new(name: "include", display_name: "Included patterns",
           required: true, content_type: :string, description: "Array of ref names or patterns to include. One of these patterns must match for the condition to pass. Also accepts `~DEFAULT_BRANCH` to include the default branch or `~ALL` to include all branches.",
           validator: method(:ensure_valid_patterns)))
        schema.add_field(ParameterSchema::Array.new(name: "exclude", display_name: "Excluded patterns",
          required: true, content_type: :string, description: "Array of ref names or patterns to exclude. The condition will not pass if any of these patterns match.",
          validator: method(:ensure_valid_patterns)))

        schema
      end

      private

      sig do
        params(
          context: RuleEngine::ParameterSchema::ValidationContext,
          patterns: T::Array[String],
          errors: T::Array[T::Hash[T.untyped, T.untyped]])
        .void
      end
      def ensure_valid_patterns(context, patterns, errors)
        invalid_patterns = []

        expected_ref_prefix = case context.root["ruleset_target"]
        when "branch"
          "refs/heads/"
        when "tag"
          "refs/tags/"
        else
          "refs/"
        end

        patterns.each do |pattern|
          next if TRANSLATED_PATTERNS.include?(pattern)

          next invalid_patterns << pattern unless pattern.start_with?(expected_ref_prefix)
          result = /\A#{expected_ref_prefix}(?<pattern>.*)\z/.match(pattern)
          # Empty strings are not valid patterns
          invalid_patterns << pattern unless !!(result && result[:pattern].present?)
        end

        return errors if invalid_patterns.empty?

        errors << {
          error_code: :invalid_pattern,
          message: "Invalid target patterns: `#{invalid_patterns.join("`, `")}`",
          value: invalid_patterns
        }
      end

      sig do
        params(
          repository: Repository,
          ruleset_target: String,
          list: T.nilable(T::Array[String]))
        .returns(T.nilable(T::Array[String]))
      end
      def replace_parameters(repository, ruleset_target, list)
        list&.map do |pattern|
          next pattern unless TRANSLATED_PATTERNS.include?(pattern)

          if pattern == ALL_PATTERN
            case ruleset_target
            when "branch"
              next "refs/heads/**/*"
            when "tag"
              next "refs/tags/**/*"
            else
              next "refs/**/*"
            end
          elsif ruleset_target == "branch" && pattern == DEFAULT_BRANCH_PATTERN
            next "refs/heads/#{repository.default_branch}"
          end

          pattern
        end
      end
    end
  end
end
