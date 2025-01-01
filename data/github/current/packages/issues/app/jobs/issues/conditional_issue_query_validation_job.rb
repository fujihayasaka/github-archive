# typed: true
# frozen_string_literal: true

require "scientist"

module Issues
  class ConditionalIssueQueryValidationJob < ApplicationJob
    queue_as :conditional_issue_query_validation

    retry_on_dirty_exit

    include Scientist

    UNMATCHABLE_PHRASES = [
      "created:>1970", # one query runs later than the other, so we'd expect there to always be a mismatch here
    ].freeze

    def perform(params = {})
      return if GitHub.enterprise?

      phrase = params.fetch(:phrase)

      # Todo: should we try specifically comparing the `ids` of the issues returned?
      #   Perhaps get a list of the issue ids returned by each query and compare
      #   using GitHub::Experiment#compare_sorted_sequence or a similar idea?
      science "search.conditional_issue_query_validation" do |experiment|
        experiment.use { issue_query_results(params) }
        experiment.try { conditional_issue_query_results(params) }

        experiment.ignore do
          phrase.in?(UNMATCHABLE_PHRASES)
        end
      end

      login = params.fetch(:current_user)&.display_login

      GitHub.logger.info("ConditionalIssueQueryValidationJob Results", {
        "gh.enduser.login": login,
        "gh.issues_advanced_search.query": phrase,
      })
    end

    def issue_query_results(params)
      query(::Search::Queries::IssueQuery, params)
    end

    def conditional_issue_query_results(params)
      query(::Search::Queries::ConditionalIssueQuery, params)
    end

    def query(klass, params)
      instance = klass.new(params)
      results = instance.execute

      {
        phrase: instance.phrase, # should this be a context on the experiment instead?
        total_results: results.total,
      }
    end
  end
end
