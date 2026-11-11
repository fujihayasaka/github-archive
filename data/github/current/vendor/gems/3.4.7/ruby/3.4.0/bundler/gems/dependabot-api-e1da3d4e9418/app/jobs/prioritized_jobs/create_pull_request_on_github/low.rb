# frozen_string_literal: true

module PrioritizedJobs
  module CreatePullRequestOnGitHub
    class Low < Default
      queue_as :create_pull_request_p3
    end
  end
end
