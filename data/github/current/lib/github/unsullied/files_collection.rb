# typed: false
# frozen_string_literal: true

module GitHub
  module Unsullied
    # An enumerable that represents all the files in a wiki repository.
    # This is for all files, not just pages.
    class FilesCollection
      # The Unsullied::Wiki object this collection is wrapping
      attr_reader :wiki

      def initialize(wiki)
        @wiki = wiki
      end

      # The GitRPC object used to perform all git operations
      delegate :rpc, to: :wiki

      # Public: Find a file in the wiki repository
      #
      # path - the full path to the file as a String
      # oid  - the revision oid (as a 40 character String) of which to attempt
      #        the lookup
      #
      # Returns a TreeEntry representing the file
      def find(path, oid = wiki.default_oid)
        match = nil
        each_file do |entry|
          if path == entry["path"]
            match = ::TreeEntry.new(wiki, entry)
            break
          end
        end
        match
      end

      # Internal: Iterate over every file in the wiki repository
      #
      # oid - the revision oid (as a 40 character string) of which to start
      #       iterating from
      #
      # Returns nothing
      def each_file(oid = wiki.default_oid, &blk)
        return if oid.nil?

        result = rpc.read_tree_entries_recursive(oid, wiki.directory_prefix, ::GitRPC::Backend::MAX_WIKI_FILES)
        result["entries"].each(&blk)
      rescue ::GitRPC::BadRepositoryState, ::GitRPC::ObjectMissing, ::GitRPC::InvalidFullOid, GitHub::DGit::UnroutedError
      end
    end
  end
end
