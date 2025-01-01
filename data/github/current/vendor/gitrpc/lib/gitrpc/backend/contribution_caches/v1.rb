# typed: true
# frozen_string_literal: true

require "zlib"
require_relative "abstract_cache"
require_relative "disk"

module GitRPC
  class Backend
    class ContributionCaches

      # Legacy custom string serialized cache file. See AbstractCache for documentation on
      # public interface.
      class V1 < AbstractCache
        include Disk

        PATH = "info/graphs"

        def initialize(backend)
          super(backend, 1)
        end

        def head_oid
          header[0]
        end

        def commits
          body.map do |line|
            parts = line.split(" ")
            if parts.size != 5 && parts.size != 6
              raise Error, "corrupt line"
            end
            [
              Integer(parts[0] || 0),
              Integer(parts[1] || 0),
              Integer(parts[2] || 0),
              Integer(parts[3] || 0),
              parts[4],
              Integer(parts[5] || 0)
            ]
          end
        end

        def write(head_sha, commits)
          validate(head_sha, commits)

          header = [head_sha, commits.size].join(" ")
          body = commits.map { |e| e.join(" ") }.join("\n")
          content = [header, body].join("\n")

          store_data(content)

          @lines = nil
          @exists = nil
        end

        private

        # Number of commits lines included in this file.
        #
        # Returns an Integer.
        def size
          Integer(header[1] || 0)
        end

        # Extract the header line from the file (first line basically) and make
        # sure it's legit. Header line looks like this:
        #
        # 7ec0d5b4384b2b2138b1d630baf0b40ec723f93f 99
        #
        # The first element is the SHA1 of the HEAD for the history covered by
        # the cache file. Second element is the number of lines that come after
        # the header line where each line is a commit.
        #
        # Returns the header tuple as an Array.
        # Raises an Error when the file is corrupt.
        def header
          parts = lines[0].split(" ")

          if parts.size != 2 || !::GitRPC::Util.valid_full_oid?(parts[0])
            raise Error, "corrupt header"
          end

          parts
        end

        # Extract the actual content of the file and memoize it. Each line
        # contains detailed stats separated for each individual commits:
        #
        # timestamp week-timestamp additions deletions email
        #
        # Returns an Array of String.
        # Raises an Error when the file is corrupt.
        def body
          body = lines[1, size]
          if body.size != size
            raise Error, "corrupt body"
          end
          body
        end

        # Read the cache file in memory and build a memoized array with each
        # line in the file as an element.
        #
        # Returns an Array of Strings.
        def lines
          @lines ||= inflated_data.split("\n")
        end
      end
    end
  end
end
