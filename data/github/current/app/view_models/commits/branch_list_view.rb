# typed: true
# frozen_string_literal: true

require "branch_sorter"

module Commits
  # Used for the commit/branch_commits partial.
  class BranchListView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    # Get the Commit object we're finding branches/tags for.
    attr_reader :commit

    # Get the branch names that contain this commit, and a list of open pull
    # requests for the given branches. If this commit has landed in the default
    # branch, then don't bother with other branches.
    #
    # In either case, look up the PR that introduced the commit (if any).
    #
    # Returns a Hash of { String branch name => [PullRequest, ...] }
    def branches_with_pull_requests
      begin
        @branches ||= if branch_names.include?(default_branch)
          { default_branch => [introductory_pull_request, parent_introductory_pull_request].compact }
        else
          branch_names.each_with_object({}) do |branch, all|
            all[branch]  = open_pull_requests.select { |pr| pr.head_ref_name == branch }
            all[branch] += [introductory_pull_request, parent_introductory_pull_request].compact
          end
        end
      rescue Commit::AssociatedPullRequestSearchFailed
        {}
      end
    end

    def pr_search_problem
      return unless commit.introductory_pull_request_search_problem

      "We’re sorry. The pull request search timed out."
    end

    # Get the tag names that point to this commit, only if this commit is in no
    # branches, or if the commit has already landed in the default branch.
    # Otherwise, just show the branches.
    #
    # Returns an Array of String tag names.
    def tags
      @tags ||= if branch_names.empty? || branch_names.include?(default_branch)
        BranchSorter.new(tag_names).reverse_each.to_a
      else
        []
      end
    end

    # Returns a list of tags that are initially hidden from view and get
    # expanded by clicking on the ellipsis.
    def hidden_tags
      tags[1..-2]
    end

    # Should we show an ellipsis placeholder denoting there are hidden tags?
    #
    # Returns Boolean.
    def abbrev_tags?
      tags.size > 2
    end

    # Public: the optional prefix a PR is given when it is referenced in a different repo.
    #
    # - pr: the PullRequest object to be referenced.
    # - current_repository: the current Repository object in which the PR will be referenced.
    #
    # Returns a String.
    def pr_prefix(pr, current_repository)
      return "" if pr.repository_id == current_repository&.id
      repo ||= (pr.repository || current_repository)
      repo.name_with_display_owner
    end

    private

    def introductory_pull_request
      return @introductory_pull_request if defined?(@introductory_pull_request)

      load_introductory_pull_requests.first
    end

    def parent_introductory_pull_request
      return @parent_introductory_pull_request if defined?(@parent_introductory_pull_request)

      load_introductory_pull_requests.second
    end

    def load_introductory_pull_requests
      async_prs = ::Promise.all([
        commit.async_introductory_pull_request(viewer: current_user),
        commit.async_parent_introductory_pull_request(viewer: current_user),
      ])
      @introductory_pull_request, @parent_introductory_pull_request = async_prs.sync
    end

    # Get the repository of this commit.
    def repository
      commit.repository
    end

    # Internal: Any open pull request involving the branches that contain this
    # commit.
    def open_pull_requests
      ref_names = Git::Ref.safe_ref_name(ref_names: branch_names)
      @open_pull_requests ||=
        if repository.feature_enabled?(:commits_by_pr_status)
          science "pulls-by-pr-status-branch-commits" do |e|
            e.use { repository.pull_requests_as_head.open_pulls.where(head_ref: ref_names) }
            e.try { repository.pull_requests_as_head.open_pull_requests_by_status.where(head_ref: ref_names) }
            e.compare_record_sequence
          end
        else
          repository.pull_requests_as_head.open_pulls.where(head_ref: ref_names)
        end
    end

    # Internal: Memoized list of branch names from GitRPC.
    def branch_names
      @branch_names ||= repository.rpc.branch_contains(commit.oid)
    rescue GitRPC::ObjectMissing
      @branch_names = []
      GitHub.dogstats.increment("branch_commits.non_existent_commit")
      @branch_names
    end

    # Internal: Memoized list of tag names from GitRPC.
    def tag_names
      @tag_names ||= repository.rpc.tag_contains(commit.oid)
    rescue GitRPC::ObjectMissing
      @tag_names = []
    end

    # Internal: The repository's default branch.
    def default_branch
      @default_branch ||= repository.default_branch
    end
  end
end
