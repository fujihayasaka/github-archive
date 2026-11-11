# typed: true
# frozen_string_literal: true

class Repository::PreferredFiles
  attr_reader :repository

  def initialize(repository:)
    @repository = repository
  end

  # Public: Gets a preferred file for a repository, if it exists.
  #
  # type   - A Symbol file type, one of `PreferredFile::TYPES`.
  # global - A Boolean indicating if we only want to return the global file
  #          from the inherited `.github` repository.
  #
  # Returns a Repository::PreferredFiles::File|nil.
  def fetch(type, global: false)
    async_fetch(type, global: global).sync
  end

  def async_fetch(type, global: false)
    # We only cache a subset of preferred files in the database. If this type
    # is one of those, we load the database record. Otherwise, we instead
    # load the `TreeEntry`.
    if RepositoryPreferredFile::VALID_TYPES.include?(type.to_s)
      async_fetch_known_file(type, global: global)
    else
      async_fetch_tree_entry(type, global: global)
    end
  end

  # Public: Indicates if a preferred file exists for this repository.
  #
  # type   - A Symbol file type, one of `PreferredFile::TYPES`.
  # global - A Boolean indicating if we only want to check for the global
  #               file from the inherited `.github` repository.
  #
  # Returns a Boolean.
  def exists?(type, global: false)
    async_exists?(type, global: global).sync
  end

  def async_exists?(type, global: false)
    async_fetch(type, global: global).then do |file|
      file.present?
    end
  end

  # Public: Checks if a given file type is only being returned from the inherited
  #         `.github` repository. This will return false if the current repository
  #         has a file of this type already.
  #
  # type - A Symbol file type, one of `PreferredFile::TYPES`.
  #
  # Returns a Boolean.
  def inherited?(type)
    return false if repository.global_health_files_repository?
    return false unless global_file = fetch(type, global: true)

    fetch(type) == global_file
  end

  # Public: Checks if a given file type is only being returned from the inherited
  #         `.github` repository. This will return false if the current repository
  #         has a file of this type already.
  #
  # type - A Symbol file type, one of `PreferredFile::TYPES`.
  #
  # Returns a Promise<Boolean>.
  def async_inherited?(type)
    return Promise.resolve(false) if repository.global_health_files_repository?
    async_fetch(type, global: true).then do |global_file|
      next false unless global_file
      async_fetch(type).then { inherited?(type) }
    end
  end

  private

  # Private: All cached preferred files associated with this repository, either
  #          locally or in the global `.github` repo.
  #
  # Returns an Promise<Array[Repository::PreferredFiles::File]>.
  def async_known_preferred_files
    @async_known_preferred_files ||= Platform::Loaders::RepositoryPreferredFiles.load(repository).then do |files|
      files.map do |file|
        Repository::PreferredFiles::File.from_record(
          record: file,
          context_repository: repository,
        )
      end
    end
  end

  # Private: All cached preferred files associated with the global `.github` repo.
  #
  # Returns an Promise<Array[Repository::PreferredFiles::File]>.
  def async_known_global_preferred_files
    return Promise.resolve([]) if repository.global_health_files_repository?

    @async_known_global_preferred_files ||= async_known_preferred_files.then do |files|
      files.select { |file| file.object.repository_id != repository.id }
    end
  end

  # Private: All cached preferred files associated with the local repo.
  #
  # Returns an Promise<Array[Repository::PreferredFiles::File]>.
  def async_known_local_preferred_files
    @async_known_local_preferred_files ||= async_known_preferred_files.then do |known_files|
      known_files.select do |file|
        file.object.repository_id == repository.id
      end
    end
  end

  # Private: Gets the cached known file for a specified type, if it exists.
  #
  # type   - A Symbol file type, one of `RepositoryPreferredFile::VALID_TYPES`.
  # global - A Boolean indicating if we only want to return the global file
  #          from the inherited `.github` repository.
  #
  # Returns a Promise<Repository::PreferredFiles::File|nil>.
  def async_known_preferred_file(type, global: false)
    known_file_promise = if global
      async_known_global_preferred_files
    else
      async_known_preferred_files
    end

    known_file_promise.then do |known_files|
      known_files.detect { |file| file.type.to_sym == type }
    end
  end

  # Private: Should we fallback to the TreeEntry for the file for this repository?
  #          This is used for GHES, where we can't run a transition to backfill
  #          `RepositoryPreferredFile` records.
  #
  # type   - A Symbol file type, one of `RepositoryPreferredFile::VALID_TYPES`.
  # global - A Boolean indicating if we only want to return the global file
  #          from the inherited `.github` repository.
  #
  # Returns a Promise<Boolean>.
  def async_fallback_to_tree_entry?(type, global: false)
    Promise.all([
      async_known_preferred_file(type, global: global),
      async_needs_initial_backfill_status
    ]).then do |file, backfill_status|
      local_needs_backfill, global_needs_backfill = backfill_status

      # We only need to fall back if the file isn't already present in the
      # known files and the parent needs a backfill OR the current repo
      # needs backfilling.
      local_needs_backfill || (file.blank? && global_needs_backfill)
    end
  end

  # Private: Fetch the known preferred file of the specified type, if it exists
  #          for this repository. If this repository doesn't have the known
  #          preferred files data cached, in the database, we'll also enqueue a
  #          job to do that.
  #
  # type   - A Symbol file type, one of `RepositoryPreferredFile::VALID_TYPES`.
  # global - A Boolean indicating if we only want to return the global file
  #          from the inherited `.github` repository.
  #
  # Returns a Promise<Repository::PreferredFiles::File|nil>.
  def async_fetch_known_file(type, global: false)
    async_fallback_to_tree_entry?(type, global: global).then do |should_fallback|
      if should_fallback
        async_enqueue_initial_backfill_job.then do
          async_fetch_tree_entry(type, global: global)
        end
      else
        async_enqueue_metadata_backfill_job.then do
          async_known_preferred_file(type, global: global)
        end
      end
    end
  end

  # Private: Returns the TreeEntry for a preferred file type, if it exists.
  #
  # type   - A Symbol file type, one of `PreferredFile::TYPES`.
  # global - A Boolean indicating if we only want to return the global file
  #          from the inherited `.github` repository.
  #
  # Returns a Promise<Repository::PreferredFiles::File|nil>.
  def async_fetch_tree_entry(type, global: false)
    @async_fetch_tree_entry ||= {}

    args = [type, global]
    return Promise.resolve(@async_fetch_tree_entry[args]) if @async_fetch_tree_entry.key?(args)

    preferred_file_promise = if global
      repository.async_global_preferred_file(type)
    else
      repository.async_preferred_file(type)
    end

    preferred_file_promise.then do |file|
      next @async_fetch_tree_entry[args] = nil if file.nil?

      @async_fetch_tree_entry[args] = Repository::PreferredFiles::File.from_tree_entry(
        type: type,
        tree_entry: file,
        context_repository: repository,
      )
    end
  end

  # Private: The global health files repository for this repository, if one exists.
  #
  # Returns a Promise<Repository|nil>.
  def async_global_health_files_repo
    repository.async_global_health_files_repo
  end

  # Private: Has a backfill job for this repository been enqueued during this
  #          instance of Repository::PreferredFiles?
  #
  # Returns a Boolean.
  def backfill_job_enqueued?
    @backfill_job_enqueued || false
  end

  # Private: Check the status of the local and global repositories to see if
  #          we need to backfill `RepositoryPreferredFile`s for either one.
  #
  # Returns a Promise<[Boolean, Boolean]> tuple, where the first item is the status of
  # the local repository, and the second is the status of the global repository.
  def async_needs_initial_backfill_status
    @async_needs_initial_backfill_status ||= async_global_health_files_repo.then do |global_repo|
      # We need to check whether the current repo or it's parent `.github` (or both) are empty
      global_promise = if global_repo.present?
        async_known_global_preferred_files
      else
        Promise.resolve([])
      end
      promises = [async_known_local_preferred_files, global_promise]

      Promise.all(promises).then do |local_known_files, global_known_files|
        unfilled_local_files = local_known_files.empty?
        unfilled_global_files = global_repo.present? && global_known_files.empty?

        [unfilled_local_files, unfilled_global_files]
      end
    end
  end

  # Private: Check the status of the local and global repositories to see if
  #          we need to backfill metadata for either one.
  #
  # Returns a Promise<[Boolean, Boolean]> tuple, where the first item is the status of
  # the local repository, and the second is the status of the global repository.
  def async_needs_metadata_backfill_status
    return @async_needs_metadata_backfill_status if defined?(@async_needs_metadata_backfill_status)

    @async_needs_metadata_backfill_status = Promise.all([
      async_known_local_preferred_files,
      async_known_global_preferred_files,
    ]).then do |local_files, global_files|
      [
        missing_cached_metadata?(files: local_files),
        missing_cached_metadata?(files: global_files),
      ]
    end
  end

  # Private: Enqueues a job to backfill `RepositoryPreferredFile` records.
  #
  #          This is used specifically for GHES, in which we don't assume any
  #          transition ran, so we may need to force run a job if the repository
  #          hasn't been 'backfilled' yet for the initial state.
  #
  #          We use the variable `backfill_job_enqueued` to avoid queueing
  #          multiple jobs on one page load.
  #
  # repositories - An Array of `Repository`s that we should enqueue a backfill
  #                job for.
  #
  # Returns nothing.
  def async_enqueue_backfill_job(backfill_self:, backfill_global:)
    return Promise.resolve(nil) if backfill_job_enqueued?

    repos = []

    global_promise = if backfill_global
      async_global_health_files_repo
    else
      Promise.resolve(nil)
    end

    global_promise.then do |global_repo|
      repos << repository if backfill_self
      repos << global_repo if global_repo.present?

      repos.each do |repo|
        RepositoryCheckPreferredFilesJob.perform_later(
          repo.id,
          repo.default_oid,
        )
      end

      @backfill_job_enqueued = true
    end
  end

  # Private: Checks if we haven't cached any preferred files for this repository
  #          and enqueues a job to backfill this data for the first time.
  #
  # Returns nothing.
  def async_enqueue_initial_backfill_job
    return Promise.resolve(nil) if backfill_job_enqueued?

    async_needs_initial_backfill_status.then do |backfill_status|
      backfill_self, backfill_global = backfill_status

      async_enqueue_backfill_job(
        backfill_self: backfill_self,
        backfill_global: backfill_global,
      )
    end
  end

  # Private: Checks if we haven't cached the `committed_at`/`has_content` values
  #          for this repository's preferred files and enqueues a job to backfill
  #          that data.
  #
  # Returns nothing.
  def async_enqueue_metadata_backfill_job
    return Promise.resolve(nil) if backfill_job_enqueued?

    async_needs_metadata_backfill_status.then do |backfill_status|
      backfill_self, backfill_global = backfill_status

      async_enqueue_backfill_job(
        backfill_self: backfill_self,
        backfill_global: backfill_global,
      )
    end
  end

  # Private: Indicates if a group of cached files are missing values for their
  #          `committed_at`/`has_content` columns.
  #
  # files - an Array of `Repository::PreferredFiles::File`s to check.
  #
  # Returns a Boolean.
  def missing_cached_metadata?(files:)
    return false if files.empty?

    # If the we've only stored the no files placeholder, we don't have
    # any files in need of backfilling.
    return false if files.first.no_files_placeholder?

    # If we haven't set `committed_at`/`has_content` for a file, we'll need
    # to run the backfill job.
    files.any?(&:missing_cached_metadata?)
  end
end
