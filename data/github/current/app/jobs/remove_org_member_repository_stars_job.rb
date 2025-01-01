# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveOrgMemberRepositoryStarsJob < LegacyRemoveOrgMemberDataJob
  queue_as :remove_org_member_repository_stars
  retry_on_dirty_exit

  BATCH_SIZE = 1000

  StarredRepository = Data.define(:star_entity, :repository)

  # For a given @user, goes through private org repositories that have stars
  # and are not pullable by the user, then removes those stars
  #
  # Saves a restorable archive of each cleared record before clearing.
  # options is used by the base class it is a hash of { "organization_id" => value, "user_id" => value }
  def perform(options)

    # CI only: ensure the bulk version of the job passes all the same tests as the non-bulk version
    if org.feature_enabled?(:remove_org_member_repo_stars_job_use_bulk_ci_only)
      BulkRemoveOrgMemberRepositoryStarsJob.perform_now(user_id: user.id, organization_ids: [org.id])
      return
    end

    last_repo_id = next_org_owned_stars_to_remove_batch(options) do |stars_batch|
      with_write do
        restorable.save_repository_stars(stars_batch.map(&:star_entity))
        Star.throttle do
          stars_batch.each { |starred_repo| @user.unstar(starred_repo.repository) }
        end
      end
    end

    if last_repo_id.nil?
      with_write { restorable.save_repository_stars_complete }
    else
      self.class.perform_later(options.merge("last_repo_id" => last_repo_id))
    end
  end

  # Yield the next batch (maximum BATCH_SIZE) of StarredRepository objects that should be unstarred because the
  # user no longer has access to the corresponding repository. Return the value of "last_repo_id" that should be
  # passed to the next job invocation in its "options" hash, if there are more repositories to process, or nil if
  # iteration is complete.
  sig do
    params(
      options: T::Hash[String, Integer],
      block: T.proc.params(repo: T::Array[StarredRepository]).void
    ).returns(T.nilable(Integer))
  end
  def next_org_owned_stars_to_remove_batch(options, &block)
    return nil unless Stars.domain.user_any_starred_repositories?(user.id)

    id_batch = next_private_org_repo_id_batch(options)
    return nil if id_batch.empty?

    # Return nil if this private repo batch was not full because that also means that there are no more private
    # repositories to find. This saves us an unnecessary job run when we know the next query would find an empty
    # batch.
    last_repo_id = id_batch.size < BATCH_SIZE ? nil : T.must(id_batch).last

    stars_in_org = Stars.domain.user_repository_stars(user.id, repo_ids: id_batch)
    return last_repo_id if stars_in_org.empty?

    repos_by_id = Repositories.domain.by_ids(stars_in_org.map(&:starrable_id)).index_by(&:id)
    inaccessible_repos = inaccessible_org_repos(repos_by_id.values).to_set
    return last_repo_id if inaccessible_repos.empty?

    stars_to_remove = stars_in_org.filter_map do |star|
      repo = repos_by_id[star.starrable_id]
      StarredRepository.new(star, repo) if inaccessible_repos.include?(repo)
    end
    return last_repo_id if stars_to_remove.empty?

    yield stars_to_remove
    last_repo_id
  end

  # Query for and return the next batch (maximum BATCH_SIZE) of IDs of private repositories in this organization.
  #
  # If options contains a "last_repo_id" key, the results will start after that ID.
  sig { params(options: T::Hash[String, Integer]).returns(T::Array[Integer]) }
  def next_private_org_repo_id_batch(options)
    last_repo_id = options.fetch("last_repo_id", -1)

    org
      .org_repositories
      .private_scope
      .where("id > ?", last_repo_id)
      .order(id: :asc)
      .limit(BATCH_SIZE)
      .pluck(:id)
  end
end
