# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2IterationFieldConfiguration < Platform::Objects::Base
      description "Iteration field configuration for a project."

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["read:project"]

      field :duration, Integer, "The iteration's duration in days", null: false
      field :start_day, Integer, "The iteration's start day of the week", null: false
      field :iterations, [Objects::ProjectV2IterationFieldIteration, null: false], "The iteration's iterations", null: false
      field :completed_iterations, [Objects::ProjectV2IterationFieldIteration, null: false], "The iteration's completed iterations", null: false
    end
  end
end
