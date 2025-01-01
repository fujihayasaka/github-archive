# typed: true
# frozen_string_literal: true

class RepositoryCheckPreferredFilesJob < ApplicationJob
  include UrlHelper

  ATTRIBUTES_FOR_NO_FILES = { filetype: RepositoryPreferredFile::NO_PREFERRED_FILES_TYPE, path: "",
    has_content: false, committed_at: nil }

  queue_as :repository_check_preferred_files

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Only one of these jobs should run at any given time when the same params are passed.
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id, commit_oid_from_ref_update)
    Failbot.push("gh.repo.id": repo_id)

    repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repo_id)
    end
    return unless repository
    return if repository.deleted?

    instrument_duration do
      # Detect if this job is out of date and should be skipped in favor of a
      # future job that will have the fresher oid
      if repository.default_oid == commit_oid_from_ref_update
        update_repo(repository, detected_files: preferred_files(repository),
          commit_oid_from_ref_update: commit_oid_from_ref_update)
      else
        # ref has been updated since the enqueue.  bail and let the next job handle this.
      end
    end
  end

  private

  def instrument_duration
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    yield

    duration_in_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
    GitHub.dogstats.distribution("repository_check_preferred_files.perform.dist.time", duration_in_ms)
  end

  # Private: This will search for the valid preferred_file types
  def preferred_files(repository)
    # This should only ever be nil if it's before any commit has been made
    default_oid = repository.default_oid || ""
    base_ref = { commit_oid: default_oid, repository_id: repository.id }
    files = []

    # We can't actually fetch files for the current commit if the default_oid
    # is blank, so we just skip this.
    if default_oid.present?
      RepositoryPreferredFile::VALID_TYPES.each do |type|
        file_attrs = file_attributes_for(repository, type: type, commitish: default_oid)
        files << base_ref.merge(file_attrs) if file_attrs
      end
    end

    files << base_ref.merge(ATTRIBUTES_FOR_NO_FILES) if files.empty?

    files
  end

  def file_attributes_for(repository, type:, commitish:)
    file = preferred_files_by_type(repository)[type]
    return unless file

    {
      filetype: type,
      path: file.path,
      has_content: file.data.present?,
      committed_at: last_commit_time_for(repository, commitish: commitish, path: file.path),
    }
  end

  # Private: Get file information about preferred files in a repository.
  #
  # Returns a Hash[String] => TreeEntry, where the keys are preferred file types. A nil value means no such preferred
  # file exists in the repository. Example:
  #
  #   {"code_of_conduct" => <TreeEntry ...>, "codeowners" => nil, "license" => <TreeEntry ...>}
  def preferred_files_by_type(repository)
    @preferred_files_by_type_by_repo_id ||= {}
    return @preferred_files_by_type_by_repo_id[repository.id] if @preferred_files_by_type_by_repo_id[repository.id]

    promises = RepositoryPreferredFile::VALID_TYPES.map do |type|
      repository.async_preferred_file(type.to_sym, check_global: false)
    end
    preferred_files = Promise.all(promises).sync

    @preferred_files_by_type_by_repo_id[repository.id] = RepositoryPreferredFile::VALID_TYPES
      .zip(preferred_files).to_h
  end

  def last_commit_time_for(repo, commitish:, path:)
    latest_commit = latest_commits_by_path(repo, commitish: commitish)[path]
    latest_commit.created_at
  end

  # Private: Get the most recent commit to affect a file in a repository.
  #
  # Returns a Hash[String] => Commit, where the keys are file paths. Example:
  #
  #   {"CODE_OF_CONDUCT.md"=> <Commit ...>, "LICENSE.md"=> <Commit ...>}
  def latest_commits_by_path(repository, commitish:)
    @latest_commits_by_path_by_repo_id ||= {}
    return @latest_commits_by_path_by_repo_id[repository.id] if @latest_commits_by_path_by_repo_id[repository.id]

    files = preferred_files_by_type(repository).values.compact
    paths = files.map(&:path)
    promises = paths.map { |path| repository.async_last_touched(commitish, path) }
    latest_commits = Promise.all(promises).sync

    @latest_commits_by_path_by_repo_id[repository.id] = paths.zip(latest_commits).to_h
  end

  def update_repo(repo, detected_files:, commit_oid_from_ref_update:)
    existing_records = existing_record_hashes_from(repo)
    return if detected_files == existing_records

    existing_file_types = existing_records.map { |record| record[:filetype] }.to_set
    not_detected_types = undetected_types_from(detected_files, existing_file_types: existing_file_types)
    detected_updated_files, detected_inserted_files = get_updates_and_inserts(detected_files,
      existing_file_types: existing_file_types)

    did_change_funding_file = changed_funding_file?(repo, existing_records: existing_records,
      detected_inserted_files: detected_inserted_files, not_detected_types: not_detected_types,
      detected_updated_files: detected_updated_files, commit_oid_from_ref_update: commit_oid_from_ref_update)
    enqueue_repo_sponsorable_jobs(repo) if did_change_funding_file

    update_repository_preferred_files(repo, detected_inserted_files: detected_inserted_files,
      detected_updated_files: detected_updated_files, not_detected_types: not_detected_types)
  end

  def get_updates_and_inserts(detected_files, existing_file_types:)
    # We need to check here if we have any existing records. If we have existing records,
    # we will want to update them directly as this is the common path.
    #
    # An upsert with MySQL cam be *very* expensive potentially in the case the record already
    # exists so it should only be used if an existing record is the exception, not the rule.
    # The reason for it being expensive is due to the so called gap lock, which means that
    # potentially far more rows will be locked in the case of an update than necessary.
    #
    # See also https://brunojorge11.medium.com/https-medium-com-brunojorge11-mysql-deadlock-insert-on-duplicate-key-update-76aa246bae72
    # for more on this topic and why this has caused availability problems in the past as well
    # such as https://github.com/github/availability/issues/1510.
    detected_updated_files, detected_inserted_files = detected_files.partition do |detected_file|
      existing_file_types.include?(detected_file[:filetype])
    end

    [detected_updated_files, detected_inserted_files]
  end

  def undetected_types_from(detected_files, existing_file_types:)
    # No need to run a delete query if we don't have anything to delete and didn't count existing things.
    not_detected_types = (RepositoryPreferredFile::ALL_TYPES - detected_files.pluck(:filetype)).to_set
    not_detected_types & existing_file_types
  end

  def existing_record_hashes_from(repo)
    repo.repository_preferred_files
      .pluck(:commit_oid, :filetype, :path, :has_content, :committed_at)
      .map do |commit_oid, filetype, path, has_content, committed_at|
        { commit_oid: commit_oid, repository_id: repo.id, filetype: filetype, path: path, has_content: has_content,
          committed_at: committed_at }
      end
  end

  def update_repository_preferred_files(repo, detected_inserted_files:, detected_updated_files:, not_detected_types:)
    RepositoryPreferredFile.throttle_writes do
      RepositoryPreferredFile.transaction do
        # Since now this is almost always an insert and never an update, we still use
        # upsert just in case. But we've removed the very common case of no updates needed
        # here at all.
        RepositoryPreferredFile.upsert_all(detected_inserted_files) if detected_inserted_files.any?
        detected_updated_files.each do |updated_file|
          RepositoryPreferredFile.where(
            repository_id: updated_file.delete(:repository_id),
            filetype: updated_file.delete(:filetype),
          ).update_all(updated_file)
        end
        if not_detected_types.any?
          repo.repository_preferred_files.where(filetype: not_detected_types).delete_all
        end
      end
    end
  end

  def changed_funding_file?(repo, existing_records:, detected_inserted_files:, not_detected_types:, detected_updated_files:, commit_oid_from_ref_update:)
    did_insert_or_delete = inserted_or_deleted_funding_file?(
      detected_inserted_files: detected_inserted_files, not_detected_types: not_detected_types,
    )
    return true if did_insert_or_delete

    updated_funding_file?(repo, existing_records: existing_records, detected_updated_files: detected_updated_files,
      commit_oid_from_ref_update: commit_oid_from_ref_update)
  end

  def enqueue_repo_sponsorable_jobs(repo)
    UpdateRepositorySponsorablesForRepositoryJob.perform_later(repository_id: repo.id)

    if repo.global_health_files_repository?
      UpdateRepositorySponsorablesForGlobalRepoJob.perform_later(repository_id: repo.id)
    end
  end

  def inserted_or_deleted_funding_file?(detected_inserted_files:, not_detected_types:)
    return false unless GitHub.sponsors_enabled?

    detected_inserted_types = detected_inserted_files.map { |file| file[:filetype] }.to_set
    modified_file_types = detected_inserted_types | not_detected_types.to_set
    modified_file_types.include?("funding")
  end

  def updated_funding_file?(repo, existing_records:, detected_updated_files:, commit_oid_from_ref_update:)
    return false unless GitHub.sponsors_enabled?

    existing_funding_file = existing_records.detect { |file| file[:filetype] == "funding" }
    return false unless existing_funding_file
    return false if commit_oid_from_ref_update == existing_funding_file[:commit_oid]

    detected_updated_types = detected_updated_files.map { |file| file[:filetype] }.to_set
    return false unless detected_updated_types.include?("funding")

    commit_oids = [existing_funding_file[:commit_oid], commit_oid_from_ref_update]
    funding_files = funding_files_for(repo, commit_oids: commit_oids)
    existing_sponsorable_ids, sponsorable_ids_in_new_commit = funding_file_sponsorable_ids_from(funding_files)

    existing_sponsorable_ids != sponsorable_ids_in_new_commit
  end

  def funding_file_sponsorable_ids_from(funding_files)
    funding_files.map do |file|
      funding_links = FundingLinks.for(blob: file.data)
      funding_links.sponsorable_ids
    end
  end

  def funding_files_for(repo, commit_oids:)
    promises = commit_oids.map do |commit_oid|
      repo.async_preferred_file(:funding, check_global: false, tree_name: commit_oid)
    end
    Promise.all(promises).sync
  end
end
