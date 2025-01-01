# typed: strict
# frozen_string_literal: true

module Commits
  module HistoryGrouper
    MERGE_PR_PATTERN = /\AMerge pull request #(\d+)/
    SQUASH_PR_PATTERN = /\(#(\d+)\)\z/ # we append (#123) to squashed commits

    class CommitGroup < T::Struct
      prop :type, Symbol
      prop :pr_number, T.nilable(Integer), default: nil
      prop :commits, T::Array[Commit]
    end

    # This helper takes a 2-step approach to logically grouping commits:
    # 1. Merge commits and squashes where we can directly suss out the PR
    # 2. Commits by the same author in a relatively short time window.
    sig { params(commits: T::Array[Commit], repository: Repository, target_branch: String).returns(T::Array[CommitGroup]) }
    def group_commits(commits, repository, target_branch)
      groups = []
      ungrouped = commits.dup

      merge_groups = extract_merge_commit_groups(ungrouped, repository, target_branch)
      groups.concat(merge_groups[:groups])
      ungrouped = merge_groups[:remaining]

      other_groups = group_by_relationship(ungrouped)
      groups.concat(other_groups)

      # Sort groups by latest commit date in descending order (most recent first)
      groups.sort_by { |group| group.commits.map(&:committed_date).compact.max || Time.at(0) }.reverse
    end

    private

    sig do
      params(commits: T::Array[Commit], repository: Repository, target_branch: String).
        returns({ groups: T::Array[CommitGroup], remaining: T::Array[Commit] })
    end
    def extract_merge_commit_groups(commits, repository, target_branch)
      groups = []
      remaining = []
      pr_to_commits = {}
      claimed = Set.new

      # First pass: Handle commits with PR numbers in commit messages
      commits.each do |commit|
        pr_number = nil
        if match = commit.message&.match(MERGE_PR_PATTERN) || commit.message&.match(SQUASH_PR_PATTERN)
          pr_number = match[1].to_i
        end

        if pr_number && commit.merge_commit? && commit.parent_oids.size == 2
          # For PR merge commits, collect both the merge commit and all branch commits
          branch_commits = collect_branch_commits_for_merge(commit, commits)
          pr_to_commits[pr_number] ||= []
          pr_to_commits[pr_number].concat(branch_commits)

          # Mark all these commits as claimed so they don't get processed again
          branch_commits.each { |c| claimed.add(c.oid) }
        elsif pr_number
          # For squash commits or other PR-related commits
          pr_to_commits[pr_number] ||= []
          pr_to_commits[pr_number] << commit
          claimed.add(commit.oid)
        elsif commit.merge_commit? && commit.parent_oids.size == 2
          unless reverse_merge?(commit, target_branch)
            # Regular merge commits without PR numbers
            merge_group = create_merge_group(commit, commits)
            groups << merge_group
            merge_group.commits.each { |c| claimed.add(c.oid) }
          end
        end
      end

      # When we are scoped to a path in the repo, we won't be able to find merge commits.
      # Here we use ElasticSearch to find PR associations for unclaimed commits.
      unclaimed_commits = commits.reject { |c| claimed.include?(c.oid) }
      if unclaimed_commits.any?
        pr_associations = find_pr_associations_for_commits(unclaimed_commits)

        pr_associations.each do |pr_number, associated_commits|
          pr_to_commits[pr_number] ||= []
          pr_to_commits[pr_number].concat(associated_commits)
          associated_commits.each { |c| claimed.add(c.oid) }
        end
      end

      # Add unclaimed commits to remaining
      commits.each do |commit|
        remaining << commit unless claimed.include?(commit.oid)
      end

      # Create PR groups
      pr_to_commits.each do |pr_number, pr_commits|
        groups << CommitGroup.new(
          type: :pull_request,
          pr_number: pr_number,
          commits: pr_commits.sort_by(&:committed_date) # chronological order
        )
      end

      { groups: groups, remaining: remaining }
    end

    sig { params(merge_commit: Commit, all_commits: T::Array[Commit]).returns(CommitGroup) }
    def create_merge_group(merge_commit, all_commits)
      # Find commits that are ancestors of this merge
      second_parent = merge_commit.parent_oids[1]
      branch_commits = [merge_commit]

      # Walk backwards from second parent to find branch commits
      to_check = [second_parent]
      checked = Set.new

      while oid = to_check.pop
        next if checked.include?(oid)
        checked.add(oid)

        commit = all_commits.find { |c| c.oid == oid }
        next unless commit

        # Stop at merge base (first parent line)
        next if commit.merge_commit?

        branch_commits << commit
        to_check.concat(commit.parent_oids) if commit.parent_oids
      end

      CommitGroup.new(
        type: :merge_commit_branch,
        commits: branch_commits.reverse # chronological order
      )
    end

    sig { params(commits: T::Array[Commit]).returns(T::Array[CommitGroup]) }
    def group_by_relationship(commits)
      return [] if commits.empty?

      groups = []
      commits.sort_by(&:committed_date).chunk_while do |a, b|
        commits_related?(a, b)
      end.each do |chunk|
        groups << CommitGroup.new(
          type: :other,
          commits: chunk
        )
      end

      groups
    end

    sig { params(a: Commit, b: Commit).returns(T::Boolean) }
    def commits_related?(a, b)
      same_author = a.author_email == b.author_email
      time_diff = (b.committed_date - a.committed_date).abs

      same_author && time_diff <= 3.days
    end

    sig { params(merge_commit: Commit, all_commits: T::Array[Commit]).returns(T::Array[Commit]) }
    def collect_branch_commits_for_merge(merge_commit, all_commits)
      # Find commits that are ancestors of this merge from the feature branch
      second_parent = merge_commit.parent_oids[1]
      first_parent = merge_commit.parent_oids[0]
      branch_commits = [merge_commit]

      # Walk backwards from second parent to find branch commits
      # Stop when we reach the merge base (a commit that's reachable from first parent)
      to_check = [second_parent]
      checked = Set.new
      first_parent_ancestors = find_ancestors(first_parent, all_commits)

      while oid = to_check.pop
        next if checked.include?(oid)
        checked.add(oid)

        commit = all_commits.find { |c| c.oid == oid }
        next unless commit

        # Stop if we reach a commit that's an ancestor of the first parent (merge base)
        next if first_parent_ancestors.include?(commit.oid)

        # Stop at other merge commits
        next if commit.merge_commit?

        branch_commits << commit
        to_check.concat(commit.parent_oids) if commit.parent_oids
      end

      branch_commits
    end

    sig { params(start_oid: String, all_commits: T::Array[Commit]).returns(T::Set[String]) }
    def find_ancestors(start_oid, all_commits)
      ancestors = Set.new
      to_check = [start_oid]

      while oid = to_check.pop
        next if ancestors.include?(oid)
        ancestors.add(oid)

        commit = all_commits.find { |c| c.oid == oid }
        next unless commit

        to_check.concat(commit.parent_oids) if commit.parent_oids
      end

      ancestors
    end

    # Try to avoid repeated calls with a batch query.
    # We'll need to sanity check that this scales acceptably.
    sig { params(commits: T::Array[Commit]).returns(T::Hash[Integer, T::Array[Commit]]) }
    def find_pr_associations_for_commits(commits)
      return {} if commits.empty?

      pr_to_commits = {}

      first_commit = commits.first
      return {} unless first_commit

      repository = first_commit.repository
      return {} unless repository

      begin
        index = Elastomer::Indexes::PullRequests.new

        # Build a batch query to search for PRs that contain any of these commits
        commit_oids = commits.map(&:oid)

        query = {
          query: {
            constant_score: {
              filter: {
                bool: {
                  must: [
                    { terms: { commits: commit_oids } },
                    { terms: { repo_id: [repository.id.to_i, repository.parent_id].compact } },
                    { term: { merged: true } }
                  ]
                }
              }
            }
          },
          _source: %w[merged_at repo_id commits number],
          sort: [{ merged_at: "asc" }],
          size: 100
        }

        result = index.search(query, type: "pull_request")
        hits = result["hits"]["hits"]

        return {} if hits.blank?

        # Process each PR hit to find which commits belong to it
        hits.each do |hit|
          pr_number = hit["_source"]["number"]
          pr_commits_oids = Set.new(hit["_source"]["commits"])
          associated_commits = commits.select { |commit| pr_commits_oids.include?(commit.oid) }
          if associated_commits.any?
            pr_to_commits[pr_number] = associated_commits
          end
        end

      rescue ElastomerClient::Client::Error, Faraday::ConnectionFailed => e
        return {}
      end

      pr_to_commits
    end

    # We skip reverse merges (merging target_branch into feature branches, like merging 'main' into your PR's branch)
    # These appear in the target_branch's history but aren't very meaningful
    sig { params(commit: Commit, target_branch: String).returns(T::Boolean) }
    def reverse_merge?(commit, target_branch)
      return false unless commit.merge_commit?
      return false unless commit.message

      commit.message.match?(reverse_merge_regexp(target_branch))
    end

    sig { params(target_branch: String).returns(Regexp) }
    def reverse_merge_regexp(target_branch)
      escaped_branch = Regexp.escape(target_branch)

      # Matches three patterns:
      # 1. Merge branch 'target_branch' into
      # 2. Merge branch 'target_branch' of https://github.com/owner/repo into
      # 3. Merge remote-tracking branch 'origin/target_branch' into
      /\AMerge (?:branch\s+['"]#{escaped_branch}['"](?:\s+of\s+https:\/\/github\.com\/[^\/\s]+\/[^\/\s]+)?|remote-tracking\s+branch\s+['"]origin\/#{escaped_branch}['"]) into\s+/
    end
  end
end
