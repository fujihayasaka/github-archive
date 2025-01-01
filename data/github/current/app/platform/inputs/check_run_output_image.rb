# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckRunOutputImage < Platform::Inputs::Base
      description "Images attached to the check run output displayed in the GitHub pull request UI."

      argument :alt, String, "The alternative text for the image.", required: true

      argument :image_url, Scalars::URI, "The full URL of the image.", required: true

      argument :caption, String, "A short image description.", required: false
    end
  end
end
