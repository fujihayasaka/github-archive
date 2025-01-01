# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryActionFeaturedState < Platform::Enums::Base
      description "The possible featured states of a repository action"
      visibility :internal

      value "FEATURED", "A featured repository action.", value: 1
      value "UNFEATURED", "An unfeatured repository action.", value: 0
    end
  end
end
