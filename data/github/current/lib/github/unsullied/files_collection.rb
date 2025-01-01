# typed: false
# frozen_string_literal: true

module GitHub
  module Unsullied
    # An enumerable that represents all the files in a wiki repository.
    # This is for all files, not just pages.
    class FilesCollection
      include Scientist

      # The Unsullied::Wiki object this collection is wrapping
      attr_reader :wiki

      def initialize(wiki)
        @wiki = wiki
      end

      # Public: Find a file in the wiki repository
      #
      # path - the full path to the file as a String
      # oid  - the revision oid (as a 40 character String) of which to attempt
      #        the lookup
      #
      # Returns a TreeEntry representing the file
      def find(path, oid = wiki.default_oid)
        match = nil
        wiki.spokes_api.list_tree_entries(tree_oid: oid, recursive: true).entries.each do |entry|
          if entry.path.name == path
            match = ::TreeEntry.new(wiki, ::TreeEntry.create_info(object: entry.object, path: path, mode: entry.mode.mode))
            break
          end
        end
        match
      rescue SpokesAPI::NotFound, SpokesAPI::InvalidArgument
        nil
      end
    end
  end
end
