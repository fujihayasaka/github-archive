# typed: true
# frozen_string_literal: true

class CodeScanningCheckSuite < ApplicationRecord::Domain::RepositoriesActionsChecks
  belongs_to :check_suite, inverse_of: :code_scanning_check_suite
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain

  validate :matches_check_suite_repository

  scope :for_check_suites, -> (check_suites, repository_id) { where(check_suite: check_suites, repository_id: repository_id) }

  def self.for_check_run(check_run)
    CodeScanningCheckSuite.find_by(check_suite: check_run.check_suite, repository: check_run.repository)
  end

  def self.code_scanning_app
    # this cluster tends to have high latency, so memoize the result
    return @code_scanning_app if defined?(@code_scanning_app)
    @code_scanning_app = Apps::Privileged.integration(:code_scanning)
  end

  sig { params(repository: T.nilable(Repository), oids: T::Array[T.nilable(String)], status: T.nilable(Symbol)).returns(T.nilable(CodeScanningCheckSuite)) }
  def self.latest_for(repository:, oids:, status: nil)
    return nil if repository.nil?

    oids.compact!

    return nil if oids.empty?
    return nil if code_scanning_app&.id.nil?

    check_suite_id = oids
      .in_groups_of(10, false)
      .lazy.filter_map do |sorted_oid_batch|
        scope = repository.check_suites
        scope = scope.where(status: CheckSuite.statuses[status]) if status.present?
        scope
          .where(head_sha: sorted_oid_batch)
          .where(github_app_id: code_scanning_app.id)
          # use the MySQL function FIELD to order the rows in the same order as sorted_oid_batch and the row
          # matching head_sha first
          .order(Arel::Nodes::NamedFunction.new("FIELD", [
            Arel.sql("head_sha"),
            *sorted_oid_batch.map(&Arel::Nodes.method(:build_quoted))
          ]))
          .pick(:id)
      end.first

    CodeScanningCheckSuite.find_by(check_suite_id: check_suite_id, repository_id: repository.id) unless check_suite_id.nil?
  end

  sig { params(pull_request: PullRequest).returns(T.nilable(String)) }
  def self.merge_commit_for(pull_request:)
    # first try the easy approach - is there exactly the check suite we are expecting?
    pull_request_sha = CodeScanningCheckSuite.where(
      repository_id: pull_request.repository_id,
      base_ref: pull_request.qualified_base_ref_name,
      base_sha: pull_request.base_sha,
      pull_request_ref: pull_request.merge_ref,
    ).order(id: :desc).pick(:pull_request_sha)
    unless pull_request_sha.nil?
      GitHub.dogstats.increment("code_scanning.merge_commit_for", tags: ["status:found"])
      return pull_request_sha.presence || pull_request.merge_commit_sha
    end

    # if not, that might mean the check suite is on a different pull request
    pull_request_sha = CodeScanningCheckSuite.latest_for(repository: pull_request.repository, oids: [pull_request.head_sha])&.pull_request_sha
    unless pull_request_sha.nil?
      GitHub.dogstats.increment("code_scanning.merge_commit_for", tags: ["status:found-fallback"])
      return pull_request_sha.presence || pull_request.merge_commit_sha
    end

    # this probably means there isn't an analysis (yet). return the merge sha so we can show it in the UI
    GitHub.dogstats.increment("code_scanning.merge_commit_for", tags: ["status:not-found"])
    pull_request.merge_commit_sha
  end

  def refs
    # Since we allow alerts from all `refs/pull/N/merge`, `refs/pull/N/head` and `refs/heads/branchname`
    # we need to select the right ones for pull_request_refs
    refs = []
    if pull_request_ref.starts_with?("refs/pull/")
      # Include pull_request_ref which may be either head or merge
      refs << pull_request_ref
      # Include `refs/pull/N/head` if pull_request_sha is `refs/pull/N/merge`
      refs << (pull_request_ref.delete_suffix("/merge") + "/head") if pull_request_ref.ends_with?("/merge")
    end
    cs = check_suite
    # Always include the branch as last option if it is available
    refs << "refs/heads/#{cs.head_branch}" if cs&.head_branch

    if refs.empty?
      error = StandardError.new("No refs for TurboScan result")
      Failbot.report(error, "gh.repo.id": repository&.id, "gh.code_scanning.code_scanning_check_suite.id": id)
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
