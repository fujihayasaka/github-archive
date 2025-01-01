# frozen_string_literal: true

class ResolveAdvisoryPRsJob < ApplicationJob
  queue_as :high

  def perform(ghsa_id:, pr_numbers:, merge:)
    pr_numbers.each do |pr_number|
      merge ? merge_pr(pr_number) : close_pr(pr_number)
    rescue Octokit::MethodNotAllowed, Octokit::Forbidden
      # Nothing to do here if PR was already closed/merged on the remote
    end
  end

  private

  def merge_pr(number)
    AdvisoryDB.github.merge_pull_request(
      AdvisoryDB.github_advisories_repo,
      number,
    )
    pull_request_author = AdvisoryDB.github.pull_request(
      AdvisoryDB.github_advisories_repo,
      number,
    ).user.login
    message = "Hi @#{pull_request_author}! Thank you so much for contributing to the GitHub Advisory Database. " \
              "This database is free, open, and accessible to all, and it's people like you who make it great. " \
              "Thanks for choosing to help others. We hope you send in more contributions in the future!"
    AdvisoryDB.github.add_comment(
      AdvisoryDB.github_advisories_repo,
      number,
      message,
    )
  end

  def close_pr(number)
    AdvisoryDB.github.close_pull_request(
      AdvisoryDB.github_advisories_repo,
      number,
    )
  end
end
