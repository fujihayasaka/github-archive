# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestStatus

  attr_reader :pull_request, :status_checks

  def initialize(pull_request:, status_checks:)
    @pull_request = pull_request
    @status_checks = status_checks
  end

  def self.load_from_pull_request(pull_request)
    Promise.all([
      pull_request.async_base_repository,
      pull_request.async_head_user,
      pull_request.async_base_user
    ]).then do |repo, _head_user, _base_user|
      repo.async_owner.then do |owner|
        owner_promise = if owner.is_a?(::User)
          owner.async_customers
        else
          Promise.resolve(nil)
        end

        owner_promise.then do
          preloader = PullRequests::PageData::StatusChecks::Preloader.new(
            repo,
            avatar_size: 40,
          )

          new(
            pull_request: pull_request,
            status_checks: PullRequests::External::Domain::StatusChecks.new.for_pull_request(pull_request, preloader: preloader),
          )
        end
      end
    end
  end
end
