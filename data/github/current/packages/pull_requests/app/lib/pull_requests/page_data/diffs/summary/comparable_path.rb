# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Summary
  class ComparablePath
    include Comparable

    sig { returns(String) }
    attr_reader :path

    sig { returns(String) }
    attr_reader :downcased_path

    sig { returns(T::Array[String]) }
    attr_reader :path_components

    sig { returns(Integer) }
    attr_reader :depth

    sig { params(path: String).void }
    def initialize(path)
      @path = T.let(path, String)
      @downcased_path = T.let(path.downcase, String)
      @path_components = T.let(path.split("/"), T::Array[String])
      @depth = T.let(@path_components.length, Integer)
    end

    # Custom sorting method that places directories before files, capitals before lowercase.
    sig { params(other: BasicObject).returns(T.nilable(Integer)) }
    def <=>(other)
      # using case equality instead of `#is_a?` to support `BasicObject`
      # which follows the built-in Sorbet type definitions for `#<=>`
      return unless ComparablePath === other # rubocop:disable Style/CaseEquality

      # if a file and a directory live at the same path, the directory comes first
      # example: "foo/bar/baz" comes before "foo/zzz"
      if self.depth != other.depth
        min_parts_length = [self.depth, other.depth].min
        self_truncated_path = T.must(self.path_components.slice(0, min_parts_length - 1))
        other_truncated_path = T.must(other.path_components.slice(0, min_parts_length - 1))

        if self_truncated_path == other_truncated_path
          # Reverse the comparison to put directories first
          # More parts means it's a directory deeper in the tree
          return other.depth <=> self.depth
        end
      end

      # Sort ignoring case, but use uppercase-first to break ties.
      [self.downcased_path, self.path] <=> [other.downcased_path, other.path]
    end
  end
end
