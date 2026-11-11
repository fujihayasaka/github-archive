# typed: true
# frozen_string_literal: true

require "spokes-proto"

module SpokesAPI
  module Types
    autoload :CommitResult, "spokes_api/types/commit_result"
    autoload :DiffAppliableResult, "spokes_api/types/diff_appliable_result"
    autoload :DiffEntry, "spokes_api/types/diff_entry"
    autoload :DiffPositionState, "spokes_api/types/diff_position_state"

    extend GitHub::Spokes::Proto::Types
  end
end
