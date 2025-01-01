# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2OrderField < Platform::Enums::Base
      description "Properties by which projects can be ordered."

      visibility :public, environments: [:dotcom, :enterprise]

      value "TITLE", "The project's title", value: "title"
      value "NUMBER", "The project's number", value: "number"
      value "UPDATED_AT", "The project's date and time of update", value: "updated_at"
      value "CREATED_AT", "The project's date and time of creation", value: "created_at"
      value "RELEVANCE", "Best match of the query compared to the project's title", value: "relevance", mobile_only: true
      value "RECENTLY_VIEWED", "Last time the project was viewed by the viewer", value: "recently_viewed", mobile_only: true
    end
  end
end
