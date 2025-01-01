# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class IssueOrPullRequest < Platform::Unions::Base
      description "Used for return value of Repository.issueOrPullRequest."

      possible_types Objects::Issue, Objects::PullRequest
    end
  end
end
