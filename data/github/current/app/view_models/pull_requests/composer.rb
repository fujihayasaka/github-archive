# typed: true
# frozen_string_literal: true

module PullRequests
  class Composer

    attr_reader :pull_request
    attr_reader :comparison

    # pull       - An existing PullRequest object to start from.
    # comparison - The Comparison we're creating a pull request off
    # options    - A Hash of Options.
    #               :expand - Should the form auto-expand? (default: false)
    def initialize(pull, comparison, options = {})
      options[:expand] ||= false

      @pull_request = pull
      @comparison = comparison
    end

    # The base repository is the repository the pull request will be merged
    # into.
    #
    # Returns a Repository.
    def base_repository
      comparison.repo
    end

    # The head repository is the repository where the new code to be merged
    # comes from.
    #
    # Returns a Repository.
    def head_repository
      comparison.head_repo
    end

    # Are there any errors on the pull request body?
    #
    # Returns a boolean.
    def show_body_errors?
      pull_request.errors[:body].any?
    end

    def commit_messages
      comparison.commits.map(&:message)
    end
  end
end
