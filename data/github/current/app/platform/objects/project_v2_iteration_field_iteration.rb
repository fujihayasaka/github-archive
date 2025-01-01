# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2IterationFieldIteration < Platform::Objects::Base
      description "Iteration field iteration settings for a project."

      class << self
        delegate :async_api_can_access?, to: Platform::Helpers::ProjectV2
        delegate :async_viewer_can_see?, to: Platform::Helpers::ProjectV2
      end

      visibility :public, environments: [:dotcom, :enterprise]

      minimum_accepted_scopes ["read:project"]

      field :id, String, "The iteration's ID.", null: false
      field :duration, Integer, "The iteration's duration in days", null: false
      field :start_date, Scalars::Date, "The iteration's start date", null: false
      field :title, String, "The iteration's title.", null: false
      field :title_html, String, "The iteration's html title.", null: false
    end
  end
end
