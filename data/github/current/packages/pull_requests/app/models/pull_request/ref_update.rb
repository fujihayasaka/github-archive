# typed: true
# frozen_string_literal: true

class PullRequest
  # A Ref Update that computes and stores the list of Pull Requests
  # that need to be synchronized as a consequence.
  class RefUpdate
    attr_reader :repository, :pusher, :qualified_refname, :before_oid, :after_oid
    def initialize(repository:, pusher:, qualified_refname:, before_oid:, after_oid:)
      @repository = repository
      @pusher = pusher
      @qualified_refname = qualified_refname
      @before_oid = before_oid
      @after_oid = after_oid
    end

    # Note: these are unqualified since they came from the `pull_requests` table.
    def refnames_from_affected_pulls          # base_ref, head_ref
      synchronizable_pulls.flat_map { |pr| [pr.base_ref, pr.head_ref] }.compact
    end

    # Returns a list of all syncable PRs that are impacted by the ref update.
    # Note: this has been augmented to replace the initial value from the db
    # (base_oid) with the *current* commit oid of the base ref, since that's
    # what we actually need for determining is-merged.
    sig { returns(T::Array[PullRequest::FindOpenPrsResult]) }
    def synchronizable_pulls
      @synchronizable_pulls ||= begin
        data = PullRequest.find_open_with_refs_based_on_ref(@repository, @qualified_refname)
        update_all_base_oids!(data)
        data
      end
    end

    # Fetch the current commit id for each base_ref, since base_sha in DB is not kept up-to-date.
    # Note: this mutates the incoming data array, rather than copying it.
    sig { params(data: T::Array[PullRequest::FindOpenPrsResult]).void }
    def update_all_base_oids!(data)
      return if data.empty?

      # Find the base repository for every PR the updated ref participates in (either as base or head)
      base_repo_ids = data.map(&:base_repo_id).uniq
      base_repos_by_id = Repository.where(id: base_repo_ids).to_h { |repo| [repo.id, repo] }

      # For each base repo, find the current base commit id for all PRs in that repo
      data
        .group_by { |pr| pr.base_repo_id }
        .each do |base_repo_id, prs_for_base_repo|
          # Very occasionally a PR will have a base repo id, but looking up that repo by ID returns nil.
          base_repo = base_repos_by_id[base_repo_id]
          next unless base_repo

          qualified_base_ref_names = prs_for_base_repo.map { |pr| "refs/heads/#{pr.base_ref}" }.uniq

          # Read current value of all base refs in this repo
          current_oids = base_repo.resolve_references(qualified_base_ref_names)
            .map { |ref, oid| [ref.delete_prefix("refs/heads/"), oid] }
            .to_h

          prs_for_base_repo.each { |pr| pr.base_oid = current_oids[pr.base_ref] }
        end
    end
  end
end
