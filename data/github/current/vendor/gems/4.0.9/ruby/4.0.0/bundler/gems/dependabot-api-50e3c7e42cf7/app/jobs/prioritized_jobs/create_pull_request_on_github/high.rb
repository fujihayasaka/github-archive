# frozen_string_literal: true

module PrioritizedJobs
  module CreatePullRequestOnGitHub
    class High < Default
      queue_as :create_pull_request_p1
    end
  end
end
