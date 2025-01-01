# typed: true
# frozen_string_literal: true
module RulesetDefinitions
  # current this module is used by both Tag and Branch rulesets since they share the same required_condition_targets
  module TargetBranch
    extend T::Sig

    sig { returns(T::Array[String]) }
    def target_required_condition_targets
      ["ref"]
    end
  end
end
