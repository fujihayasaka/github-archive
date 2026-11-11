# typed: strict
# frozen_string_literal: true

require File.expand_path("query_binder.rb", __dir__)
Dir[File.expand_path("scorecard_jobs/*.rb", __dir__)].each { |f| require f }

module ServiceCatalog
  class Client
    # ScorecardJobsQueryBinder contains methods for accessing scorecard jobs.
    class ScorecardJobsQueryBinder < QueryBinder
      # A default scorecard job detail fragment.
      SCORECARD_JOB_DETAIL_FRAGMENT = <<~GRAPHQL
        fragment ScorecardJobDetail on ScorecardJob {
          id
          jobId
          status
          updatedAt
          createdAt
          scorecard {
            id
            name
          }
          service {
            id
            name
          }
        }
      GRAPHQL
    end
  end
end
