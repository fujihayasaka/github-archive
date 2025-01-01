# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "spokes-proto"

module SpokesAPI
  module Types
    autoload :DiffEntry, "spokes_api/types/diff_entry"

    extend GitHub::Spokes::Proto::Types
  end
end
