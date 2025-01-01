# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrant
  module RepositorySelection
    ALL = :all
    NONE = :none
    SUBSET = :subset

    OPTIONS = [ALL, NONE, SUBSET].freeze

    OPTION_ORDER = {
      NONE => 0,
      SUBSET => 1,
      ALL => 2,
    }.with_indifferent_access.freeze
  end
end
