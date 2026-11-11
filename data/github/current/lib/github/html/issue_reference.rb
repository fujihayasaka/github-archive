# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Object added to the result hash to record issue references.
  class IssueReference
    attr_accessor :issue, :type, :readable
    alias_method :readable?, :readable

    def initialize(issue, type, readable = false)
      @issue = issue
      @type  = type
      @readable = readable
    end

    def async_repo_and_owner
      issue.async_repository.then do |repo|
        next unless repo
        repo.async_owner
      end
    end

    def async_pull_request
      issue.async_pull_request
    end

    def pull_request?
      issue.pull_request?
    end

    def close?
      type.to_s =~ /\b(close|fix|resolve)/i
    end

    def duplicate?
      type.to_s =~ /\b(duplicate of)/i
    end

    def hash
      issue.hash ^ type.hash
    end

    def belonging
      issue
    end

    def ==(other)
      issue == other.issue
    end
    alias_method :eql?, :==
  end
end
