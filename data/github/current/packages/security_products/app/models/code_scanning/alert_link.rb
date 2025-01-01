# typed: strict
# frozen_string_literal: true

# This class represents the link between one code scanning alert and a single branch or pull request.
# Alert links are loaded from turboscan and then enriched with branch/PR data.
module CodeScanning
  class AlertLink
    extend T::Sig

    sig { returns(Integer) }
    attr_accessor :repository_id

    sig { returns(Integer) }
    attr_accessor :alert_number

    sig { returns(T.nilable(String)) }
    attr_accessor :branch

    sig { returns(T.nilable(PullRequest)) }
    attr_accessor :pull_request

    sig do
      params(
        repository_id: Integer,
        alert_number: Integer,
        branch: T.nilable(String),
        pull_request: T.nilable(PullRequest)
      ).void
    end
    def initialize(repository_id:, alert_number:, branch:, pull_request:)
      @repository_id = repository_id
      @alert_number = alert_number
      @branch = branch
      @pull_request = pull_request
    end
  end
end
