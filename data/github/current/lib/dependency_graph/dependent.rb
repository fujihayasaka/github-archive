# typed: true
# frozen_string_literal: true

module DependencyGraph
  class Dependent
    attr_reader :cursor

    def self.wrap(dependents)
      dependents.map { |attrs| new(attrs["node"], cursor: attrs["cursor"]) }
    end

    def initialize(attrs, cursor: nil)
      @attrs  = attrs
      @cursor = cursor
    end

    def repository_id
      @attrs["repositoryId"]
    end

    def name
      @attrs["name"]
    end

    def manifest_path
      File.join([
        @attrs["manifestPath"],
        @attrs["manifestFilename"],
      ].reject(&:blank?))
    end

    def manifest_blob_path
      return unless repository.present?
      return @manifest_blob_path if defined? @manifest_blob_path

      repo_blob_path = Addressable::Template.new("/{owner}/{name}/blob/{branch}/").expand(
        branch: repository.default_branch,
        name: repository.name,
        owner: repository.owner.to_s,
      )
      # Use URI joining here to append the manifest path, given that it's user-generated and we don't know what'll be there
      @manifest_blob_path = repo_blob_path.join(manifest_path)
    end

    def requirements
      @attrs["requirements"]
    end

    def platform_type_name
      "DependencyGraphDependent"
    end

    def repository
      async_repository.sync
    end

    def scope
      @attrs["scope"]
    end

    def async_repository
      return @async_repository if defined? @async_repository

      @async_repository = Platform::Loaders::ActiveRecord.load(::Repository, repository_id, security_violation_behaviour: :nil).then do |repo|
        next nil unless repo

        # FIXME: This is a patch to work around orphaned repos.
        # Remove after https://github.com/github/github/issues/130381 is resolved.
        repo.async_owner.then do |owner|
          next repo if owner
        end
      end
    end
  end
end
