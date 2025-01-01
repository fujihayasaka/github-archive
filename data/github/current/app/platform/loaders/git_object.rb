# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class GitObject < Platform::Loader
      include Scientist

      def self.load(repository, oid, expected_type: nil, alternate_repositories: [], path_prefix: nil, timeout: nil)
        return Promise.resolve(nil) unless GitRPC::Util.valid_full_sha1?(oid)

        async_prepared_repositories(repository, alternate_repositories).then do |repositories|
          self.for(repositories, expected_type: expected_type, path_prefix: path_prefix, timeout: timeout).load(oid)
        end
      end

      def self.load_all(repository, oids, expected_type: nil, alternate_repositories: [], path_prefix: nil, timeout: nil)
        async_prepared_repositories(repository, alternate_repositories).then do |repositories|
          loader = self.for(repositories, expected_type: expected_type, path_prefix: path_prefix, timeout: timeout)

          Promise.all(oids.map { |oid| loader.load(oid) })
        end
      end

      def self.async_prepared_repositories(repository, alternate_repositories)
        alternate_repositories.compact!
        alternate_repositories.sort!

        repositories = alternate_repositories
        repositories.unshift(repository) if repository
        repositories.uniq!

        Promise.all([
          Promise.all(repositories.map(&:async_name_with_owner)),
          Promise.all(repositories.map(&:async_network)),
        ]).then do
          repositories
        end
      end

      def initialize(repositories, expected_type: nil, path_prefix: nil, timeout: nil)
        @repository, *alternate_repositories = repositories
        @expected_type = expected_type.nil? ? nil : expected_type.to_s.freeze
        @path_prefix = path_prefix
        @timeout = timeout

        if alternate_repositories.any?
          @rpc = @repository.build_rpc
          @rpc.options[:alternates] = @repository.alternate_object_paths_for(*alternate_repositories)
        else
          @rpc = @repository.rpc
        end
      end

      def fetch(oids)
        if @timeout && @timeout > 0
          @rpc.with_timeout(@timeout) do
            @rpc.read_objects(oids, @expected_type, true).map { |info| info_to_object(info) }.to_h
          end
        else
          @rpc.read_objects(oids, @expected_type, true).map { |info| info_to_object(info) }.to_h
        end
      end

      private

      def info_to_object(git_data)
        klass = case git_data["type"]
        when "blob"
          ::Blob
        when "commit"
          ::Commit
        when "tag"
          ::Tag
        when "tree"
          if @path_prefix
            # If we are loading in the context of a larger tree (whose
            # path is stored in @path_prefix), do this slightly silly
            # duplication to ensure TreeEntry#path works correctly.
            git_data["entries"].transform_values { |entry| entry["path"] = entry["name"] }
          end
          ::Tree
        else
          raise Platform::Errors::Type, "unknown git type: #{git_object["type"].inspect}"
        end
        object = klass.new(@repository, git_data)
        if object.instance_of?(Tree)
          object.entries.each { |entry| entry.path_prefix = @path_prefix }
        end
        [git_data["oid"], object]
      end
    end
  end
end
