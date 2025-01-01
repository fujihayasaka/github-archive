# typed: true
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class RepositoryNameTarget < FnmatchIncludeExcludeTarget
      TRANSLATED_PATTERNS = T.let([
        "~ALL"
      ], T::Array[String])

      def target_value(context)
        context.repository.name
      end

      sig { override.returns(T::Boolean) }
      def internal?
        false
      end

      sig { override.returns(String) }
      def target_object
        "repository"
      end

      sig { override.returns(T::Array[Symbol]) }
      def supported_ruleset_targets
        [:branch, :tag, :push, :member_privilege]
      end

      # Sources that support this condition target
      sig { override.returns(T::Array[Symbol]) }
      def supported_sources
        [:organization, :business]
      end

      sig do
        override.params(
          targetable: Targetable,
          ruleset_target: String,
          parameters: T.untyped
        ).returns(T::Boolean)
      end
      def run_condition(targetable, ruleset_target, parameters)
        return false unless (repository = targetable.repository)

        include_list = replace_parameters(repository, ruleset_target, parameters["include"])
        exclude_list = replace_parameters(repository, ruleset_target, parameters["exclude"])
        match_include_exclude(target_value(targetable), include_list, exclude_list) do |candidate, target|
          File.fnmatch?(candidate, target, File::FNM_PATHNAME | File::FNM_DOTMATCH)
        end
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

          if pattern == "~ALL"
            next "*"
          end

          pattern
        end
      end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root(validator: method(:ensure_valid_include_exclude_condition))

        schema.add_field(ParameterSchema::Field.new(name: "protected", display_name: "Prevent matching targets from being changed",
          required: false, default_value: false, type: :boolean, description: "Target changes that match these patterns will be prevented except by those with bypass permissions."))
        schema.add_field(ParameterSchema::Array.new(name: "include", display_name: "Included patterns",
           required: true, content_type: :string, description: "Array of repository names or patterns to include. One of these patterns must match for the condition to pass. Also accepts `~ALL` to include all repositories.",
           validator: method(:ensure_valid_patterns)))
        schema.add_field(ParameterSchema::Array.new(name: "exclude", display_name: "Excluded patterns",
          required: true, content_type: :string, description: "Array of repository names or patterns to exclude. The condition will not pass if any of these patterns match.",
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

        patterns.each do |pattern|
          # Empty strings are not valid patterns
          invalid_patterns << pattern unless pattern.strip.present?
        end

        return errors if invalid_patterns.empty?

        errors << {
          error_code: :invalid_pattern,
          message: "Invalid target patterns: `#{invalid_patterns.join("`, `")}`",
          value: invalid_patterns
        }
      end
    end
  end
end
