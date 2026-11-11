# typed: true
# frozen_string_literal: true

# This mixin should include any generic or cross-cutting preferred file logic to be considered
# part of the repo_info service. Preferred files that are owned by specific services should be
# in their own files, e.g. community_dependency has license, code of conduct, etc.
module Repository::PreferredFilesDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))
    has_many :repository_preferred_files, dependent: :destroy, inverse_of: :repository

    scope :with_global_health_files_name, -> { where(name: Repository::GLOBAL_HEALTH_FILES_NAME) }

    # Public: The global health files repository for this repository, if one exists.
    #
    # Returns a Repository or nil.
    batch_method :global_health_files_repo do |repos|
      results = Promise.all(repos.map(&:async_global_health_files_repo)).sync
      repos.zip(results).to_h
    end
  end

  # Public: Creates an instance of Repository::PreferredFiles,
  #         which allows accessing preferred files for this repository.
  #
  # Returns a Repository::PreferredFiles instance.
  def preferred_files
    @preferred_files ||= Repository::PreferredFiles.new(repository: self)
  end

  # Public: Find preferred files from PreferredFile::Types.
  #
  # Searched from the root for the default_branch and in the global community health repo
  # if one is not found locally.
  #
  #  - type         - One of PreferredFile::TYPES
  #  - check_global - Whether to search the global community health repo for
  #                   the preferred file if one is not found locally.
  #  - tree_name    - The name of a specific branch to find the preferred file in.
  #
  # Returns a TreeEntry or nil.
  def preferred_file(type, check_global: true, tree_name: nil)
    async_preferred_file(type, check_global: check_global, tree_name: tree_name).sync
  end

  def async_preferred_file(type, check_global: true, tree_name: nil)
    @async_preferred_files ||= {}
    args = [type, check_global, tree_name]
    return Promise.resolve(@async_preferred_files[args]) if @async_preferred_files.key?(args)
    access.async_broken?.then do |broken|
      next @async_preferred_files[args] = nil if broken

      Promise.all([async_default_branch, async_root]).then do |default_branch, _|
        local_file = begin
          PreferredFile.find(
            directory: directory(tree_name || default_branch),
            type: type,
          )
        rescue GitRPC::ObjectMissing
          nil
        end

        next @async_preferred_files[args] = local_file unless local_file.nil?
        next @async_preferred_files[args] = nil unless check_global

        async_global_preferred_file(type).then do |global_file|
          @async_preferred_files[args] = global_file
        end
      end
    end
  end

  # Public: The global health files repository for this repository, if one exists.
  #
  # Returns a Promise<Repository|nil>.
  def async_global_health_files_repo
    return Promise.resolve(nil) if global_health_files_repository?
    return Promise.resolve(@global_health_files_repo) if defined?(@global_health_files_repo)
    Platform::Loaders::GlobalHealthFilesRepository.load(owner_id).then do |global_health_files_repo|
      @global_health_files_repo = global_health_files_repo
    end
  end

  # Public: Find the preferred file that can be inherited for this repository
  #         from the global `.github` repository.
  #
  # type - A Symbol file type, one of `PreferredFile::TYPES`.
  #
  # Returns a Promise<TreeEntry|nil>.
  def async_global_preferred_file(type)
    return Promise.resolve(nil) unless PreferredFile::GLOBAL_TYPES.include?(type)
    return Promise.resolve(nil) if global_health_files_repository?

    async_global_health_files_repo.then do |global_repository|
      next unless global_repository.present?

      global_repository.async_default_branch.then do |default_branch|
        PreferredFile.find(
          directory: global_repository.directory(default_branch),
          type: type,
        )
      end
    end
  end
end
