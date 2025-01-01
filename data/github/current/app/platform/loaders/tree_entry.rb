# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class TreeEntry < Platform::Loader
      def self.load(repository, treeish_oid, path)
        self.for(repository).load([treeish_oid, path])
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(treeish_oid_and_path_pairs)
        treeish_oid_and_path_pairs.map do |pair|
          tree_entry = begin
            # TODO: It'd be great to batch these loads, but that'd require a new GitRPC endpoint.
            @repository.blob(*pair)
          rescue GitRPC::ObjectMissing, GitRPC::InvalidObject, GitHub::DGit::UnroutedError
            nil
          end

          [pair, tree_entry]
        end.to_h
      end
    end
  end
end
