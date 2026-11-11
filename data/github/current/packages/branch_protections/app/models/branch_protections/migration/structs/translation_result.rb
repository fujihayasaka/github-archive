# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Structs
      class TranslationResult < T::Struct
        const :rule_type, String
        const :parameters, T.nilable(T::Hash[Symbol, T.untyped]), default: {}
        const :bypass_actors, T::Array[BypassActor], default: []
      end
    end
  end
end
