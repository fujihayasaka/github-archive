# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # Returns the result of a tree_file_list call for a given tree.
    class GitTreeFileList < Platform::Loader

      def self.load(repository, tree_oid)
        self.for(repository).load(tree_oid)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(tree_oids)
        tree_oids.each_with_object({}) do |tree_oid, result|
          result[tree_oid] = @repository.tree_file_list(tree_oid)
        end
      end
    end
  end
end
