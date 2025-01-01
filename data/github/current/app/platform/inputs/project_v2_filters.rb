# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2Filters < Platform::Inputs::Base
      description "Ways in which to filter lists of projects."

      argument :state,
        Enums::ProjectV2State,
        "List project v2 filtered by the state given.",
        required: false
    end
  end
end
