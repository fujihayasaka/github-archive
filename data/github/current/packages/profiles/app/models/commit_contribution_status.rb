# typed: true
# frozen_string_literal: true

class CommitContributionStatus
  attr_reader :commit

  def initialize(commit)
    @commit = commit
  end

  def email_linked?
    !commit.author.nil?
  end

  def in_upstream_default?
    cmt_branches = commit.repository.rpc.branch_contains(commit.oid)
    !commit.repository.fork? &&
      CommitContribution.branches(commit.repository).any? { |branch| cmt_branches.include?(branch) }
  end

  def repo_valid?
    return false unless commit.author

    validator = CommitContribution::RepositoryValidator.new(commit.author, repository_ids: [commit.repository.id])
    validator.valid_repository?(commit.repository.id)
  end

  def internal_repo?
    commit.repository.internal?
  end
end
