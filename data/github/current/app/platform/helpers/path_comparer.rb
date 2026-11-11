# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class PathComparer
      # custom sorting method, like the spaceship operator (<=>) it
      # returns -1 if a comes first
      # returns 0 if a and b are the same
      # returns 1 if b comes first
      def self.compare_paths(a, b)
        a_parts = a.split("/")
        b_parts = b.split("/")

        # if a file and a directory live at the same path, the file comes first
        # example: "foo/zzz" comes before "foo/bar/baz"
        if a_parts.length != b_parts.length
          min_parts_length = [a_parts.length, b_parts.length].min
          a_truncated_path = a_parts.slice(0, min_parts_length - 1).join("/")
          b_truncated_path = b_parts.slice(0, min_parts_length - 1).join("/")
          if a_truncated_path == b_truncated_path
            return a_parts.length <=> b_parts.length
          end
        end

        if a.downcase == b.downcase
          # we want capitals to come after lowercase, which
          # is reversed from normal order
          b <=> a
        else
          a.downcase <=> b.downcase
        end
      end
    end
  end
end
