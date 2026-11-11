# frozen_string_literal: true

module PrioritizedJobs
  module CreatePullRequestOnGitHub
    class Default < ApplicationJob
      module Metrics
        def increment_metric(name, tags: {})
          update_job.increment_metric(name, tags: ppr_metric_tags.merge(tags))
        end

        def ppr_metric_tags
          {
            grouped_update: pending_pr.grouped_update?,
            v2: true,
          }
        end
      end
    end
  end
end
