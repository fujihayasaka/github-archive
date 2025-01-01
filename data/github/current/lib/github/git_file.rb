# typed: true
# frozen_string_literal: true

module GitHub
  module GitFile
    class << self # rubocop:disable Style/ClassMethodsDefinitions
      IGNORED_CODEPOINTS = [
        0x200c, 0x200d, 0x200e, 0x200f,
        0x202a, 0x202b, 0x202c, 0x202d,
        0x202e, 0x206a, 0x206b, 0x206c,
        0x206d, 0x206e, 0x206f, 0xfeff
      ]

      def validate_component(comp)
        # Empty components are invalid in a tree
        return false if comp.empty?

        # Trivial cases: `.git` in upper/lowercase, and the path
        # traversal components
        return false if [".git", ".", ".."].include?(comp.downcase)

        # HFS+ normalization:
        # Convert path to its codepoints (assume UTF-8), then remove
        # any of the magical ignored codepoints. If the remaining
        # codepoints still equal ".git", then reject the component
        #
        # Note that we skip the check if the encoding is broken (it
        # cannot be folded then) or if we only have an ASCII range
        # in the path
        comp.force_encoding("UTF-8")
        if comp.valid_encoding? && !comp.ascii_only?
          cp = comp.downcase.codepoints.reject { |c| IGNORED_CODEPOINTS.include? c }
          return false if cp == [46, 103, 105, 116] # '.git'
        end

        # NTFS normalization:
        # Try to remove the trailing prefix, either `.git` or a 8.3
        # prefix `GIT~1`. If the string had either of those prefixes,
        # then make sure that:
        #
        # - The remainder of the string does not start with a backslash,
        # e.g. `.git\`, or `GIT~1\`
        # - The remainder of the string is not only periods and spaces,
        # as trailing periods and spaces at the end are removed by NTFS
        if comp.slice!(/^\.git/i) || comp.slice!(/^GIT~1/i)
          return false if comp.starts_with?("\\")
          return false if comp.chars.all? { |c| c == " " || c == "." }
        end

        # If we've passed all these checks, the component is probably safe
        true
      end

      def validate_path(path)
        return "cannot be blank" if path.blank?
        return "cannot start with a slash" if path.starts_with?("/")
        return "cannot end with a slash" if path.ends_with?("/")
        return "contains a malformed path component" if path.split("/").any? { |p| !validate_component(p) }
        nil
      end
    end
  end
end
