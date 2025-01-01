# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "spokes-proto"

module SpokesAPI
  module Types
    autoload :DiffEntry, "spokes_api/types/diff_entry"
    autoload :DiffPositionState, "spokes_api/types/diff_position_state"

    extend GitHub::Spokes::Proto::Types
  end
end
