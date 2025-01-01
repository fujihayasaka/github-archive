# typed: true
# frozen_string_literal: true

class Repository::PreferredFiles::File
  attr_reader :type, :object, :context_repository

  # record - a RepositoryPreferredFile.
  def self.from_record(record:, context_repository:)
    new(type: record.filetype.to_sym, object: record, context_repository: context_repository)
  end

  # type - A Symbol file type, one of enum `filetype`s from `RepositoryPreferredFile`.
  # tree_entry - A TreeEntry.
  def self.from_tree_entry(type:, tree_entry:, context_repository:)
    new(type: type, object: tree_entry, context_repository: context_repository)
  end

  # type - A Symbol file type, one of enum `filetype`s from `RepositoryPreferredFile`.
  # object - A RepositoryPreferredFile|TreeEntry.
  # context_repository - The Repository we are rendering this information for.
  #                      We require this to avoid having to load the repository
  #                      association, and instead can compare the IDs.
  def initialize(type:, object:, context_repository:)
    @type               = type
    @object             = object
    @context_repository = context_repository
  end

  # Public: The path to this file in the repository.
  #
  # Returns a String.
  def path
    object.path
  end

  # Public: The git commit oid for this file.
  #
  # Returns a String.
  def commit_oid
    if cached?
      object.commit_oid
    else
      object.repository.default_oid
    end
  end

  # Public: The repository that this file resides in.
  #
  # Returns a Repository.
  def repository
    async_repository.sync
  end

  def async_repository
    return Promise.resolve(object.repository) if tree_entry?
    object.async_repository
  end

  # Public: The TreeEntry for this preferred file.
  #         NOTE: It is possible for the TreeEntry to be nil if the cached data
  #         is out of date. Be sure to ensure that it is present when after you
  #         call this.
  #
  # Returns a TreeEntry|nil.
  def tree_entry
    return @tree_entry if defined?(@tree_entry)
    @tree_entry = async_tree_entry.sync
  end

  def async_tree_entry
    return @async_tree_entry if defined?(@async_tree_entry)
    return @async_tree_entry = Promise.resolve(object) if tree_entry?

    @async_tree_entry = async_repository.then do |repo|
      begin
        PreferredFile.find(
          directory: repo.directory(commit_oid),
          type: type,
        )
      rescue GitRPC::ObjectMissing
        Promise.resolve(nil)
      end
    end
  end

  # Public: The filename of the preferred file, derived from the path.
  #
  # Returns a String.
  def filename
    @filename ||= path.split("/")[-1]
  end

  # Public: The name of the repository this file is in.
  #
  #
  # Returns a String.
  def repository_name
    repo_id = tree_entry? ? object.repository.id : object.repository_id

    if repo_id == context_repository.id
      context_repository.name
    else
      Repository::GLOBAL_HEALTH_FILES_NAME
    end
  end

  # Public: The URL pointing to this file in the repository at the commit_oid or default_branch.
  #         This is a work-around instead of using `blob_view_path` as this
  #         won't cover the case of distinguishing whether the preferred file
  #         lives in .github, or the current repository.
  #         For example, `/test-org/.github/blob/deadbeef/CODE_OF_CONDUCT.md` is
  #         a case where `blob_view_path` wouldn't correctly use `.github`.
  #
  # include_host - A Boolean indicating if `GitHub.url` should be prepended to
  #                path to this file.
  # use_oid      - A Boolean indicating if the url should use the `commit_oid`
  #                instead of the default branch.
  #
  # Returns a String.
  def permalink(include_host: false, use_oid: true)
    nwo = "#{context_repository.owner_display_login}/#{repository_name}"
    oid_or_branch = use_oid ? commit_oid : repository.default_branch
    blob_path = "/#{nwo}/blob/#{oid_or_branch}/#{path}"

    include_host ? "#{GitHub.url}#{blob_path}" : blob_path
  end

  # Public: Does this record not have a cached `committed_at` and `has_content`
  #         stored? We didn't always store these values, so we need to check
  #         to see if we need to backfill this data. As a Boolean, `has_content`
  #         defaults to `false`, so we check if `committed_at` is nil to see
  #         if we've set these values for this file.
  #
  # Returns a Boolean.
  def missing_cached_metadata?
    return false unless cached?
    object.committed_at.blank?
  end

  # Public: Indicates if this file is the placeholder that we create when a
  #         repository does not have any preferred files.
  #
  # Returns a Boolean.
  def no_files_placeholder?
    type == RepositoryPreferredFile::NO_PREFERRED_FILES_TYPE.to_sym
  end

  # Public: Is this file loaded from the cached RepositoryPreferredFile record?
  #
  # Returns a Boolean.
  def cached?
    object.is_a?(RepositoryPreferredFile)
  end

  # Public: Is this file loaded from the actual TreeEntry from the repository?
  #
  # Returns a Boolean.
  def tree_entry?
    object.is_a?(TreeEntry)
  end
end
