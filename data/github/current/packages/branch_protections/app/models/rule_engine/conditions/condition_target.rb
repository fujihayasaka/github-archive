# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Conditions
    class ConditionTarget
      extend T::Sig
      extend T::Helpers
      include Validations
      abstract!

      sig do
        abstract.params(
          targetable: Targetable,
          ruleset_target: String,
          parameters: T.untyped
        ).returns(T::Boolean)
      end
      def run_condition(targetable, ruleset_target, parameters); end

      # Internal conditions are under development and should not be exposed to users
      sig { abstract.returns(T::Boolean) }
      def internal?; end

      # What object does this condition look at? (ex: Repository)
      sig { abstract.returns(String) }
      def target_object; end

      # What ruleset targets does this condition support? (ex: branch, tag, push)
      sig { abstract.returns(T::Array[Symbol]) }
      def supported_ruleset_targets; end

      # Sources that support this condition target
      sig { abstract.returns(T::Array[Symbol]) }
      def supported_sources; end

      # Allows rules to provide the Ruleset edit UI with additional metadata
      sig do
        overridable.params(ruleset: RepositoryRuleset, parameters: T::Hash[String, T.untyped])
        .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
      end
      def edit_ui_metadata(ruleset, parameters)
        nil
      end

      protected

      sig do
        params(
          target: String,
          include_list: T.nilable(T::Array[String]),
          exclude_list: T.nilable(T::Array[String]),
          blk: T.proc.params(candidate: String, target: String).returns(T::Boolean))
         .returns(T::Boolean)
      end
      def match_include_exclude(target, include_list, exclude_list, &blk)

        return false if include_list.blank? && exclude_list.blank?

        matches_include = include_list.nil? || include_list.empty? || include_list.any? do |candidate|
          yield(candidate, target)
        end

        matches_exclude = exclude_list&.any? do |candidate|
          yield(candidate, target)
        end

        matches_include && !matches_exclude
      end
    end
  end
end
