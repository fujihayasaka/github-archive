# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckRunOutput < Platform::Inputs::Base
      description "Descriptive details about the check run."

      argument :title, String, "A title to provide for this check run.", required: true

      argument :summary, String, "The summary of the check run (supports Commonmark).", required: true

      argument :text, String, "The details of the check run (supports Commonmark).", required: false

      argument :annotations, [Inputs::CheckAnnotationData], "The annotations that are made as part of the check run.", required: false

      argument :images, [Inputs::CheckRunOutputImage], "Images attached to the check run output displayed in the GitHub pull request UI.", required: false
    end
  end
end
