# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DraftPullRequestReviewComment < Platform::Inputs::Base
      description "Specifies a review comment to be left with a Pull Request Review."

      argument :path, String, "Path to the file being commented on.", required: true
      argument :position, Integer, "Position in the file to leave a comment on.", required: true
      argument :body, String, "Body of the comment to leave.", required: true
    end
  end
end
