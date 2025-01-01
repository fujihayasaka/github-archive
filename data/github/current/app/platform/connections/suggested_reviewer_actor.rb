# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class SuggestedReviewerActor < Connections::Base
      description "A suggestion to review a pull request based on an actor's commit history, review comments, and integrations."

      total_count_field
    end
  end
end
