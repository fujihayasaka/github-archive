# typed: strict
# frozen_string_literal: true

class CopilotSpace
  # Uses the Spokes API to resolve file information for a collection of files in a repository.
  # Spokes can resolve up to 1000 files at a time per their [API documentation](https://github.com/github/spokes-proto/blob/2372843b95d63dcc0aac017bda7aa2a4d41c050f/gen/docs/spokes-api/objects/v1/objects_api.md#resolveobjects)
  class GitHubFileCollection

    class GitFileInfo < T::Struct
      const :file_resource, CopilotSpaceResource
      const :exists, T::Boolean
      const :size, Integer
      const :size_percentage, Float
    end

    sig { returns(T::Array[CopilotSpaceResource]) }
    attr_reader :file_resources

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(Float) }
    attr_reader :max_content_size

    sig { returns(T::Array[CopilotSpaceResource]) }
    attr_reader :valid_encoding_file_resources

    sig { returns(T::Array[CopilotSpaceResource]) }
    attr_reader :invalid_encoding_file_resources

    sig { params(max_content_size: Float, repository: Repository, file_resources: T::Array[CopilotSpaceResource]).void }
    def initialize(max_content_size:, repository:, file_resources:)
      @max_content_size = T.let(max_content_size, Float)
      @repository = T.let(repository, Repository)
      @file_resources = T.let(file_resources, T::Array[CopilotSpaceResource])
      unless file_resources.all?(&:github_file_resource_type?)
        raise ArgumentError, "All resources must be GitHub file resources"
      end

      # Process encoding validation in a single pass during initialization
      @valid_encoding_file_resources = T.let([], T::Array[CopilotSpaceResource])
      @invalid_encoding_file_resources = T.let([], T::Array[CopilotSpaceResource])

      file_resources.each do |resource|
        meta = resource.metadata
        file_path = meta["file_path"]

        if file_path.dup.force_encoding("utf-8").valid_encoding?
          @valid_encoding_file_resources << resource
        else
          @invalid_encoding_file_resources << resource
          GitHub.dogstats.increment("github.copilot.copilot_space.file_collection.encoding.invalid", tags: ["encoding:#{file_path.encoding.name}"])
          GitHub.logger.warn("File path encoding invalid, skipping from Spokes API call", {
            "gh.copilot.copilot_space.file.path": file_path,
            "gh.copilot.copilot_space.file.encoding": file_path.encoding.name,
          })
        end
      end
    end

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def spokes_arguments
      shas = valid_encoding_file_resources.map { |resource| resource.metadata["sha"] || repository.default_branch }.uniq
      sha_to_oid = shas.each_with_object({}) do |sha, hash|
        hash[sha] = repository.ref_to_sha(sha)
      end

      spokes_args = valid_encoding_file_resources.map do |resource|
        meta = resource.metadata
        oid = sha_to_oid[meta["sha"]] || repository.default_oid
        {
          by_treeish_and_path: {
            treeish: { oid: { id: oid } },
            path: { name: normalize_git_path(meta["file_path"]) }
          }
        }
      end
    end

    sig { returns(T::Array[GitFileInfo]) }
    def git_info
      # Get results from Spokes API for files with valid encodings
      if valid_encoding_file_resources.empty?
        # If no files have valid encodings, return GitFileInfo with exists: false for all
        return file_resources.map do |file_resource|
          GitFileInfo.new(
            file_resource: file_resource,
            exists: false,
            size: 0,
            size_percentage: 0.0
          )
        end
      end

      response = T.let(repository.spokes_api.resolve_objects_by(spokes_arguments), GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse)
      returned_items = response.items

      # Create a mapping from file_resource to GitFileInfo
      valid_resource_to_git_info = returned_items.map.with_index do |item, index|
        # See https://github.com/github/spokes-proto/blob/2372843b95d63dcc0aac017bda7aa2a4d41c050f/proto/spokes-api/objects/v1/objects_api.proto#L134
        # for the structure of the item. It'll either be an error string or an object.
        item = T.let(item, GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem)
        size = item.object&.size || 0
        file_resource = T.must(valid_encoding_file_resources[index])
        [file_resource, GitFileInfo.new(
          file_resource: file_resource,
          # In the future we might handle the separate error messages differently, but for now we just check if the object is present.
          exists: item.object.present?,
          size: size,
          size_percentage: (size / max_content_size * 100).round(10).to_f
        )]
      end.to_h

      # Return GitFileInfo for all original file_resources in order
      file_resources.map do |file_resource|
        valid_resource_to_git_info[file_resource] || GitFileInfo.new(
          file_resource: file_resource,
          exists: false, # Files with invalid encoding are treated as non-existent
          size: 0,
          size_percentage: 0.0
        )
      end
    end

    # Normalize and validate a path within a Git tree for use with the Spokes API.
    sig { params(path: T.nilable(String)).returns(T.nilable(String)) }
    def normalize_git_path(path)
      path = SpokesAPI::Util.normalize_path(path)&.gsub(/\/$/, "") # trim trailing directory separators
      return if path.nil?

      # Explicitly block paths that start with "." or ".."
      first_component = Pathname.new(path).each_filename.first
      raise GitRPC::NoSuchPath, "the path '#{first_component}' does not exist in the given tree" if %w[. ..].include?(first_component)

      path
    end
  end
end
