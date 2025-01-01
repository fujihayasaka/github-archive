# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module TargetMemberPrivilege
    extend T::Sig

    sig { returns(T::Array[String]) }
    def target_required_condition_targets
      []
    end
  end
end
