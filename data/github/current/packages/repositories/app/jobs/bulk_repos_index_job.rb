# typed: true
# frozen_string_literal: true

# Repair job to reindex all repositories for a given org
# It's based on RepairJob so it takes advantage of the batch processing
# and Redis synchronization, using a custom group_key to allow multiple
# jobs of this kind to run in parallel for different orgs.

# IMPORTANT: This job adds & updates documents, but does not remove them from ES, see remove_stale_documents below

class BulkReposIndexJob < Elastomer::RepairJob
  LIMIT = 250
  MAX_JOBS = 5

  class AdminnedOrgIdActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    def initialize(organization_id)
      @organization_id = organization_id
    end

    def flipper_id
      "Organization:#{@organization_id}"
    end

    def vexi_id
      flipper_id
    end
  end

  sig { params(business: Business).returns(T::Array[BulkReposIndexJob]) }
  def self.reindex_business(business)
    org_ids = business.organizations.ids
    reindex_org(org_ids)
  end

  sig { params(org_id: T.any(Integer, T::Array[Integer])).returns(T::Array[BulkReposIndexJob]) }
  def self.reindex_org(org_id)
    org_ids = Array(org_id)
    org_ids.delete_if do |id|
      if GitHub.flipper[:skip_bulk_repos_index_job].enabled?(AdminnedOrgIdActor.new(id))
        GitHub.logger.info("Skipping BulkReposIndexJob", {
          "gh.organization.id" => id,
        })
        true
      end
    end

    return [] if org_ids.empty?

    repos_count = Repository.where(owner_id: org_ids).count
    return [] if repos_count == 0

    jobs_count = (repos_count - 1) / LIMIT + 1
    jobs_count = [jobs_count, MAX_JOBS].min
    Elastomer.router.writable(Elastomer::Indexes::Repos).map do |index|
      reindex_orgs_on_index(index.name, org_ids, jobs_count)
    end
  end

  sig { params(index_name: String, org_id: T::Array[Integer], jobs_count: Integer).returns(BulkReposIndexJob) }
  private_class_method def self.reindex_orgs_on_index(index_name, org_id, jobs_count = 1)
    job = BulkReposIndexJob.new(index_name, org_id: org_id)
    job.reset! if job.exists?
    job.enable
    job.start(jobs_count)
    job
  end

  retry_on_dirty_exit

  queue_as :index_bulk

  reconcile "repository",
    force_reindex: true,
    limit: LIMIT,
    accept: :repo_is_searchable?,
    include: %i(
      internal_repository
      mirror
      network
      repository_license
      owner
      topics
    ),
    conditions: proc { |_, job|
      "repositories.owner_id IN (#{job.org_id.join(',')})"
    },
    prefills: %i(
      custom_properties_effective_values
      sponsorable_owner?
    ),
    # This job cannot yet remove documents from ES for 2 reasons:
    # 1. It would delete documents that don't fit into the given `conditions:`
    # 2. Performance is bad because the id_range for ES is too large
    # So by now we limit this job to only add/update documents
    delete_documents_from_es: false

  def group_key
    return @group_key if @group_key

    # We can run this job in parallel for multiple orgs, so the key needs to be distinct
    @group_key = "#{super}/org:#{org_id}"
  end

  def org_id
    _, opts = job_args
    # Ensure we return an array because in-progress jobs may have been queued with an integer
    # The Array() call can be removed after the transition period
    Array(opts.fetch(:org_id))
  end
end
