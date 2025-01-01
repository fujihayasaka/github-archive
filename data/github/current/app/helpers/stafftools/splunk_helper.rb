# typed: true
# frozen_string_literal: true

module Stafftools
  module SplunkHelper
    extend T::Sig

    SPLUNK_URL = "https://splunk.githubapp.com/en-US/app/gh_reference_app/search"

    # Public: Generates a url to splunk
    #
    # Returns splunk url, or nothing for enterprise installations
    sig { params(params: Hash).returns(T.nilable(String)) }
    def splunk_url(params)
      return if GitHub.enterprise?

      "#{SPLUNK_URL}?#{params.to_query}"
    end

    # Public: Generates a url to search splunk
    #
    # Returns splunk url, or nothing for enterprise installations
    sig { params(search: String).returns(T.nilable(String)) }
    def splunk_search_url(search)
      splunk_url({ q: search })
    end

    # Public: Generates a url to search splunk for an orchestration
    #
    # Returns splunk url, or nothing for enterprise installations
    sig { params(orchestration: T.any(RepositoryOrchestration, PullRequestOrchestration)).returns(T.nilable(String)) }
    def splunk_orchestration_url(orchestration)
      orchestration_query = case orchestration
      when RepositoryOrchestration
        "gh.repo.orchestration.id=#{orchestration.id}"
      when PullRequestOrchestration
        "gh.pull_request.orchestration.id=#{orchestration.id}"
      end

      splunk_url({
          "q": "index IN (rails, prod-exceptions, prod-resque) #{orchestration_query}",
          "earliest": orchestration.created_at.to_i,
          "latest": orchestration.updated_at.to_i + 10.minutes.to_i
        })
    end
  end
end
