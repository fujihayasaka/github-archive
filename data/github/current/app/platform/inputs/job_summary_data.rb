# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class JobSummaryData < Platform::Inputs::Base
      description "Summary URL for a workflow job."
      visibility :internal
      argument :url, Scalars::URI, "The URL where this summary can be found.", required: true
    end
  end
end
