# typed: true
# frozen_string_literal: true

class CodeScanningCheckSuite < ApplicationRecord::Domain::RepositoriesActionsChecks
  extend T::Sig

  belongs_to :check_suite, inverse_of: :code_scanning_check_suite
  belongs_to :repository

  validate :matches_check_suite_repository

  scope :for_check_suites, -> (check_suites, repository_id) { where(check_suite: check_suites, repository_id: repository_id) }

  def self.for_check_run(check_run)
    CodeScanningCheckSuite.find_by(check_suite: check_run.check_suite, repository: check_run.repository)
  end

  sig { params(pull_request: PullRequest).returns(T.nilable(String)) }
  def self.merge_commit_for(pull_request:)
    CodeScanningCheckSuite.where(
      repository_id: pull_request.repository_id,
      base_ref: pull_request.qualified_base_ref_name,
      base_sha: pull_request.base_sha,
      pull_request_ref: pull_request.merge_ref,
    ).order(id: :desc).pick(:pull_request_sha) || pull_request.merge_commit_sha
  end

  def refs
    # Since we allow alerts from all `refs/pull/N/merge`, `refs/pull/N/head` and `refs/heads/branchname`
    # we need to select the right ones for pull_request_refs
    refs = []
    if self.pull_request_ref.starts_with?("refs/pull/")
      # Include pull_request_ref which may be either head or merge
      refs << self.pull_request_ref
      # Include `refs/pull/N/head` if pull_request_sha is `refs/pull/N/merge`
      refs << (self.pull_request_ref.delete_suffix("/merge") + "/head") if self.pull_request_ref.ends_with?("/merge")
    end
    cs = self.check_suite
    # Always include the branch as last option if it is available
    refs << "refs/heads/#{cs.head_branch}" if cs&.head_branch

    if refs.empty?
      error = StandardError.new("No refs for TurboScan result")
      Failbot.report(error, "gh.repo.id": repository&.id, "gh.code_scanning.code_scanning_check_suite.id": self.id)
    end
    refs
  end

  def refs_bytes
    refs.map(&:b)
  end

  private

  def matches_check_suite_repository
    cs = check_suite
    return if cs.nil?
    if repository_id != cs.repository_id
      errors.add(:repository, "does not match the workflow run's repository")
    end
  end
end
