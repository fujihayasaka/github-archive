# typed: true
# frozen_string_literal: true

require "zlib"
require "msgpack"

module GitRPC
  class Backend
    class ContributionCaches

      # MessagePack based cache file
      class V2 < AbstractCache
        include Disk

        PATH = "info/contribution-cache-2.msgpack.gz"

        def initialize(backend)
          super(backend, 2)
        end

        def head_oid
          full_data[0]
        end
        alias head_sha head_oid

        def commits
          full_data[1]
        end

        def write(head_oid, commits)
          validate(head_oid, commits)

          data = MessagePack.pack([head_oid, commits])
          store_data(data)

          # make the cached ivar match the newly written object
          @full_data = data
        end

        private

        def full_data
          return @full_data if defined?(@full_data)
          @full_data = MessagePack.unpack(inflated_data)
        end
      end
    end
  end
end
