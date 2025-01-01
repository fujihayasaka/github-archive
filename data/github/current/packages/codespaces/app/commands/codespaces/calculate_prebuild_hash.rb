# typed: true
# frozen_string_literal: true

module Codespaces
  class CalculatePrebuildHash < Command
    # The properties which reference files whose contents also affect the
    # prebuild hash
    DEVCONTAINER_REFERENCED_FILES = %w(postCreateCommand onCreateCommand)

    # The list of files that should be hashed to determine the prebuild hash
    HASHED_FILES = %w(Dockerfile)

    # The user-specified files which invalidate the prebuild cache
    HASH_PATHS_KEY = "prebuildHashPaths"

    # The default cap on the size of ls-tree output we'll handle
    DEFAULT_TREE_BYTE_LIMIT = 7.megabyte.freeze

    # How long we should cache hash calculations for
    CACHE_EXPIRATION = 30.days

    def initialize(repository:, oid:, tree_byte_limit: DEFAULT_TREE_BYTE_LIMIT, cache: Codespaces::Kv.store, devcontainer_path: nil)
      @repository = repository
      @oid = oid
      @tree_byte_limit = tree_byte_limit
      @cache = cache
      @devcontainer_path = devcontainer_path
    end

    def perform
      prebuild_cache_key = "codespaces:prebuild:#{@repository.id}:#{@oid}"
      prebuild_cache_key += ":#{@devcontainer_path}" if @devcontainer_path
      existing = @cache.get(prebuild_cache_key).value { nil }
      GitHub.dogstats.increment("codespaces.create.prebuilds.oid_cache", tags: ["result:#{existing ? "hit" : "miss"}"])
      return existing if existing

      hash = calculate_hash || @oid
      set_cache(prebuild_cache_key, hash)
      hash
    end

    private

    def set_cache(prebuild_cache_key, hash)
      ActiveRecord::Base.connected_to(role: :writing) do
        @cache.set(prebuild_cache_key, hash, expires: CACHE_EXPIRATION.days.from_now)
      end
    end

    def get_dockerfile_path_ifexists(devcontainer:)
      if @devcontainer_path.nil?
        common_path = File.dirname(Codespaces::DevContainer.get_default_path(@repository, @oid))
      else
        common_path = File.dirname(@devcontainer_path)
      end

      if devcontainer.build.dockerfile.empty?
        nil
      else
        File.join(common_path, devcontainer.build.dockerfile)
      end
    end

    def calculate_hash
      GitHub.dogstats.distribution_time("codespaces.calculate_prebuild_hash.calculate_hash.latency") do
        devcontainer = Codespaces::DevContainer.new(repository: @repository, oid: @oid, filepath: @devcontainer_path)
        return nil unless devcontainer.exists?

        referenced_files = DEVCONTAINER_REFERENCED_FILES.map { |prop| devcontainer[prop] }
        prebuild_hash_paths = Array(devcontainer[HASH_PATHS_KEY])
        dockerfile_path = get_dockerfile_path_ifexists(devcontainer: devcontainer)

        oids = begin
          result = @repository.rpc.ls_tree(@oid, long: true, recurse: true, show_trees: true, byte_limit: @tree_byte_limit)
          truncated = result["truncated"]
          entries = {}
          result["entries"].each do |entry|
            entry = TreeEntry.from_ls_tree(@repository, entry, from_collection: true)
            entries[entry.path] = entry
          end

          GitHub.dogstats.count("codespaces.prebuilds.ls_tree_count", entries.size, tags: ["truncated:#{truncated}"])

          [*HASHED_FILES, *referenced_files, *prebuild_hash_paths, dockerfile_path].flat_map do |path|
            entry = entries[path]
            entry ? entry.oid : []
          end
        rescue GitRPC::NoSuchPath, GitRPC::ObjectMissing, GitRPC::InvalidObject, GitRPC::InvalidRepository
          nil
        end
        return nil unless oids

        Digest::SHA256.hexdigest("#{devcontainer.tree_entry.oid}:#{oids.join(":")}")
      end
    end
  end
end
