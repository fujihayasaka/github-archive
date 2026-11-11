# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Structs
      class BypassActor < T::Struct
        const :actor_type, String
        const :actor_id, T.nilable(Integer)
        const :bypass_mode, String
      end
    end
  end
end
