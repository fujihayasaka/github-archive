# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class StorageState < Platform::Enums::Base
      description "The possible storage states."

      visibility :internal, environments: [:dotcom]

      ::Storage::Uploadable::STATES.each do |state, _|
        value state.upcase, "State is #{state}.", value: state
      end
    end
  end
end
