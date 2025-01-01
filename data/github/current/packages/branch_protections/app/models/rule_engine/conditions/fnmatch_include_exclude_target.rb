# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    # Abstract class for conditions that match a target based on a regex (with incluing and excluding lists)
    class FnmatchIncludeExcludeTarget < ConditionTarget
      extend T::Helpers
      abstract!

      sig do
        override.params(
          targetable: Targetable,
          ruleset_target: String,
          parameters: T.untyped
        ).returns(T::Boolean)
      end
      def run_condition(targetable, ruleset_target, parameters)
        match_include_exclude(target_value(targetable), parameters["include"], parameters["exclude"]) do |candidate, target|
          File.fnmatch?(candidate, target, File::FNM_PATHNAME)
        end
      end

      sig { abstract.params(targetable: Targetable).returns(String) }
      def target_value(targetable); end

      sig { override.returns(RuleEngine::ParameterSchema::Object) }
      def parameter_schema
        schema = ParameterSchema::Object.root

        schema.add_field(ParameterSchema::Field.new(name: "protected", display_name: "Prevent matching targets from being changed",
          required: false, default_value: false, type: :boolean, description: "Target changes that match these patterns will be prevented except by those with bypass permissions."))
        schema.add_field(ParameterSchema::Array.new(name: "include", display_name: "Included patterns",
           required: true, content_type: :string, description: "One of these patterns must match for the condition to pass."))
        schema.add_field(ParameterSchema::Array.new(name: "exclude", display_name: "Excluded patterns",
          required: true, content_type: :string, description: "The condition will not pass if any of these patterns match."))

        schema
      end
    end
  end
end
