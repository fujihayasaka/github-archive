# typed: strict
# frozen_string_literal: true

module Repos::BranchesViewDependency
  extend T::Helpers
  include ApplicationHelper
  include BranchesHelper
  include UrlHelpers

  BranchPayload = T.type_alias do
    {
      name: String,
      isDefault: T::Boolean,
      mergeQueueEnabled: T::Boolean,
      path: String,
      rulesetsPath: T.nilable(String),
      protectedByBranchProtections: T::Boolean,
      author: T.nilable({
        login: String,
        name: String,
        avatarUrl: String,
        path: String,
      }),
      authoredDate: Time,
      deleteable: T::Boolean,
      deleteProtected: T::Boolean,
      renameable: T::Boolean,
      isBeingRenamed: T::Boolean,
    }
  end

  BranchMetadataPayload = T.type_alias do
    {
      oid: String,
      aheadBehind: T.nilable(T::Array[Integer]),
      maxDiverged: T.nilable(Integer), # The max number of ahead/behind commits for a branch in the payload
      statusCheckRollup: T.nilable({ state: Symbol, shortText: T.nilable(String) }),
      pullRequest: T.nilable({
        number: Integer,
        title: String,
        permalink: String,
        status: String,
        reviewableState: String,
        merged: T::Boolean
      }),
      mergeQueue: T.nilable({
        path: String,
        count: Integer
      })
    }
  end

  BranchPaginatedPayload = T.type_alias do
    {
      current_page: T.nilable(Integer),
      has_more: T.nilable(T::Boolean),
      per_page: T.nilable(Integer),
      branches: T::Array[BranchPayload],
    }
  end

  # Inherits from ApplicationController
  sig { returns(T.nilable(Repository)) }
  def current_repository
    super
  end

  sig { returns(T.nilable(User)) }
  def current_user
    super
  end

  sig do
    returns({
      branches: {
        default: T.nilable(BranchPayload),
        yours: T::Array[BranchPayload],
        active: T::Array[BranchPayload]
      },
      hasMore: {
        yours: T::Boolean,
        active: T::Boolean
      },
      protectThisBranchBanner: {
        dismissed: T::Boolean,
        isSecurityAdvisory: T::Boolean
      }
    })
  end
  def branches_overview_payload
    finder = branch_finder(5)
    default = finder.default_branch

    all_branches = [finder.default_branch, finder.your_branches, finder.active_branches].compact.flatten
    GitHub::PrefillAssociations.prefill_batch_method(all_branches.map(&:ref), :policy_evaluator)

    {
      branches: {
        default: default ? extract_branch_fields(default) : nil,
        yours: finder.your_branches.map { |branch| extract_branch_fields(branch) },
        active: finder.active_branches.map { |branch| extract_branch_fields(branch) },
      },
      hasMore: {
        yours: finder.your_branches.has_more,
        active: finder.active_branches.has_more,
      },
      protectThisBranchBanner: {
        dismissed: !show_protect_this_branch_banner?(T.must(current_repository).default_branch),
        isSecurityAdvisory: T.must(current_repository).advisory_workspace?,
      },
    }
  end

  sig { params(type: Symbol, page: T.nilable(Integer), query: T.nilable(String)).returns(BranchPaginatedPayload) }
  def branches_list_payload(type, page = nil, query = nil)
    finder = branch_finder(20, page, query)

    branches = T.let([], T::Array[T.untyped])
    if query.present?
      branches = finder.query_branches
    else
      branches = case type
      when :yours
        finder.your_branches
      when :active
        finder.active_branches
      when :stale
        finder.stale_branches
      when :all
        finder.all_branches(include_default_branch: true)
      else
        raise "Type not supported: #{type}"
      end
    end

    GitHub::PrefillAssociations.prefill_batch_method(branches.map(&:ref), :policy_evaluator)

    {
      current_page: branches.current_page,
      has_more: branches.has_more,
      per_page: branches.per_page,
      branches: branches.map { |branch| extract_branch_fields(branch) }
    }
  end

  sig { params(branch_names: T::Array[String], include_authors: T.nilable(T::Boolean)).returns(T::Hash[String, BranchMetadataPayload]) }
  def branches_metadata(branch_names, include_authors: false)
    return {} if current_repository.nil?

    repository = T.must(current_repository)
    ref_names = branch_names.uniq.map { |name| "refs/heads/#{name}" }
    branches = repository.heads.find_all(ref_names).compact

    GitHub.dogstats.count("branches_view.deleted_branches", ref_names.size - branches.size)
    # If we find branches that do not actually exist, we should delete them from the RefPush table
    if ref_names.size > branches.size
      RefPushReactiveCleanupJob.perform_later(repository.id, ref_names - branches.map(&:qualified_name))
    end

    head_commits_by_sha = T.must(current_repository).commits.find(branches.map(&:sha)).index_by(&:sha)
    head_commits_by_ref_name = Hash[branches.map { |branch| [branch.name, head_commits_by_sha[branch.sha]] }]

    base_sha = head_commits_by_ref_name[repository.default_branch]&.oid || repository.heads.find(repository.default_branch.b).sha

    pull_requests_by_ref_name = load_pull_requests_by_ref_name(head_commits_by_ref_name)
    ahead_behind_by_sha = load_ahead_behind_by_sha(base_sha, head_commits_by_sha.keys)
    max_diverged = ahead_behind_by_sha.values.flatten.max || 0

    Promise.all(head_commits_by_sha.values.map { |commit| commit.status_check_rollup }).sync
    Promise.all(head_commits_by_sha.values.map { |commit| commit.author_actor.async_visible_actor(current_user) }).sync if include_authors

    Hash[branches.map do |branch|
      pull_request = pull_requests_by_ref_name[branch.name]
      status_check_rollup = head_commits_by_ref_name[branch.name]&.status_check_rollup.as_json(only: %w[state short_text])
      merge_queue = if branch.default_branch?
        merge_queue_for_branch(branch.name)
      else
        nil
      end
      author = head_commits_by_ref_name[branch.name]&.author_actor.async_visible_actor(current_user).sync if include_authors

      [
        branch.name,
        {
          oid: branch.sha,
          aheadBehind: ahead_behind_by_sha[branch.sha],
          maxDiverged: max_diverged,
          statusCheckRollup: if status_check_rollup.present?
                               {
                                 state: status_check_rollup["state"],
                                 shortText: status_check_rollup["short_text"],
                               }
                             else
                               nil
                             end,
          pullRequest: if pull_request.present?
                         {
                           number: pull_request.issue&.number,
                           title: pull_request.issue&.title,
                           state: pull_request.issue&.state,
                           reviewableState: pull_request.reviewable_state,
                           merged: pull_request.merged?,
                           permalink: pull_request.permalink,
                           isPullRequest: true
                         }
                       else
                         nil
                       end,
          mergeQueue: if merge_queue.present?
                        {
                          path: merge_queue_path(merge_queue_branch: branch.name),
                          count: number_with_delimiter(merge_queue.entries.count)
                        }
                      else
                        nil
                      end,
          author: if author.present? && author != User.ghost
                    {
                      login: author.display_login,
                      name: author.name,
                      avatarUrl: author.primary_avatar_url(32),
                      path: user_path(author)
                    }
                  else
                    nil
                  end

        }
      ]
    end]
  end

  private

  sig { params(limit: Integer, page: T.nilable(Integer), query: T.nilable(String)).returns(::Branches::BranchFinder) }
  def branch_finder(limit = 20, page = nil, query = nil)
    ::Branches::BranchFinder.new(
      current_repository,
      current_user,
      limit:,
      query:,
      page:,
    )
  end

  sig { params(branch: Branches::BranchFinder::Branch).returns(BranchPayload) }
  def extract_branch_fields(branch)
    protected_by = T.let({ rulesets: false, branch_protections: false }, { rulesets: T::Boolean, branch_protections: T::Boolean })

    is_protected = current_repository&.plan_supports?(:protected_branches) && branch.ref.protected?

    if current_repository&.plan_supports?(:protected_branches)
      protected_by = {
        rulesets: branch.ref.protected_by_ruleset?,
        branch_protections: branch.ref.protected_by_protected_branch?
      }
    end

    {
      name: branch.ref.name,
      isDefault: branch.ref.default_branch?,
      mergeQueueEnabled: merge_queue_for_branch(branch.ref.name).present?,
      path: tree_path("", branch.ref.name, current_repository),
      rulesetsPath: if protected_by[:rulesets]
                      view_repository_rulesets_path(T.must(current_repository).owner, current_repository, ref: branch.ref.qualified_name)
                    else
                      nil
                    end,
      protectedByBranchProtections: protected_by[:branch_protections],
      author: if branch.author.present? && branch.author != User.ghost
                {
                  login: branch.author.display_login,
                  name: branch.author.name,
                  avatarUrl: branch.author.primary_avatar_url(32),
                  path: user_path(branch.author)
                }
              else
                nil
              end,
      authoredDate: branch.committer_date,
      deleteable: branch.ref.deleteable?(deleter: current_user),
      deleteProtected: is_protected && branch.ref.policy_evaluator&.blocks_deletes_for?(current_user),
      isBeingRenamed: branch.ref.repository.branch_being_renamed?(branch.ref.name.b),
      renameable: current_repository&.ref_renameable_by?(current_user, ref: branch.ref) || false,
    }
  end

  sig { params(head_commits_by_ref_name: T::Hash[String, Commit]).returns(T::Hash[String, PullRequest]) }
  def load_pull_requests_by_ref_name(head_commits_by_ref_name)
    return {} if current_repository.nil?

    PullRequest.
      includes(:issue).
      where(
        head_repository_id: T.must(current_repository).id,
        base_repository_id: T.must(current_repository).id,
        head_ref: head_commits_by_ref_name.keys,
      ).select do |pull|
        pull.head_sha == head_commits_by_ref_name[pull.head_ref]&.oid
      end.index_by do |pull|
        pull.head_ref
      end
  end

  sig { params(base_sha: String, other_shas: T::Array[String]).returns(T::Hash[String, T::Array[Integer]]) }
  def load_ahead_behind_by_sha(base_sha, other_shas)
    return {} if current_repository.nil?

    ahead_or_behind_shas, equivalent_shas = other_shas.partition { |sha| sha != base_sha }

    ahead_behind = T.must(current_repository).rpc.ahead_behind(base_sha, ahead_or_behind_shas)

    equivalent_shas.each do |sha|
      ahead_behind[sha] = [0, 0]
    end

    ahead_behind
  end

  sig { params(name: String).returns(T.nilable(MergeQueue)) }
  def merge_queue_for_branch(name)
    return nil unless current_repository&.merge_queue_enabled?

    current_repository&.merge_queue_for(branch: name)
  end
end
